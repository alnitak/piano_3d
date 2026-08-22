import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:soundfont_kit/soundfont_kit.dart';

/// Manages audio initialization, SoundFont playback, and real-time FFT data extraction.
class AudioController {
  static final AudioController instance = AudioController._();
  AudioController._();

  SoundFontFile? _soundFont;
  SoundFontPlayer? _player;
  AudioData? _audioData;
  bool _isInitialized = false;
  bool _isPreloaded = false;
  double _preloadProgress = 0.0;
  String? _statusMessage;

  // Active playing keys tracking
  final Map<int, SoundFontVoice> _activeVoices = {};
  final Set<int> _pressedKeys = {};

  // FFT buffer for visualization
  final Float32List _fftBuffer = Float32List(166); // Bins 15 to 180 inclusive (166 bins)
  final Float32List _smoothedFft = Float32List(166);
  
  // Continuous 256 rows x 512 cols history texture buffer
  final Float32List _historyTexture = Float32List(256 * 512);

  bool get isInitialized => _isInitialized;
  bool get isPreloaded => _isPreloaded;
  double get preloadProgress => _preloadProgress;
  String? get statusMessage => _statusMessage;
  SoundFontFile? get soundFont => _soundFont;
  SoundFontPlayer? get player => _player;
  List<Preset> get presets => _soundFont?.presets ?? [];
  Float32List get fftData => _smoothedFft;
  Float32List get texture2dData => _historyTexture;
  bool get hasActiveAudio =>
      _activeVoices.isNotEmpty || _pressedKeys.isNotEmpty;

  /// Initializes SoLoud with the "Render-ahead ring" configuration and loads the SoundFont.
  Future<void> initialize({
    String soundFontAsset = 'assets/SFX_StarWars_weapons.SF2',
    void Function(double progress)? onProgress,
  }) async {
    if (_isInitialized) return;

    _statusMessage = 'Initializing SoLoud audio engine...';

    // Initialize SoLoud with Render-ahead ring as per requirement
    await SoLoud.instance.init(
      bufferSize: 1024,
      devicePeriodFrames: 128,
      renderAheadFrames: 0,
    );
    SoLoud.instance.setMaxActiveVoiceCount(32);
    SoLoud.instance.setAudioDeviceIdleTimeout(null);
    SoLoud.instance.setVisualizationEnabled(true);

    _statusMessage = 'Loading SoundFont: $soundFontAsset...';

    try {
      _soundFont = await SoundFontFile.fromAsset(soundFontAsset);
      _player = _soundFont!.createPlayer();

      _player!.sustainMultiplier = 0.01;
      _player!.sustainTime = 0.01;

      // Initialize 2D texture audio data for FFT extraction (256 rows x 512 cols)
      _audioData = AudioData(GetSamplesKind.texture);

      _statusMessage = 'Preloading SoundFont samples...';
      _isPreloaded = false;

      // Preload all audio samples for zero-latency playback
      await _player!.preloadAll(
        onProgress: (progress, loaded, total) {
          _preloadProgress = progress;
          onProgress?.call(progress);
        },
      );

      _isPreloaded = true;
      _isInitialized = true;
      _statusMessage = 'Ready (${_soundFont!.presets.length} presets loaded)';
    } catch (e) {
      _statusMessage = 'Error initializing audio: $e';
      debugPrint('AudioController initialization error: $e');
    }
  }

  /// Plays a note for a key index using the mapped preset from the SoundFont.
  Future<void> playNote({
    required int keyIndex,
    required int midiNote,
    int velocity = 110,
    int? customPresetIndex,
  }) async {
    if (_player == null || _soundFont == null) return;
    _pressedKeys.add(midiNote);

    final availablePresets = _soundFont!.presets;
    Preset? targetPreset;

    if (availablePresets.isNotEmpty) {
      final index = customPresetIndex ?? (keyIndex % availablePresets.length);
      targetPreset =
          availablePresets[index.clamp(0, availablePresets.length - 1)];
    }

    try {
      final voice = await _player!.noteOn(
        midiNote,
        preset: targetPreset,
        velocity: velocity,
      );
      _activeVoices[midiNote] = voice;
    } catch (e) {
      debugPrint('Error playing note $midiNote: $e');
    }
  }

  /// Releases the note for the given midi note.
  Future<void> stopNote(int midiNote) async {
    _pressedKeys.remove(midiNote);
    final voice = _activeVoices.remove(midiNote);
    if (voice != null) {
      try {
        await voice.release();
      } catch (_) {}
    }
    if (_player != null) {
      try {
        await _player!.noteOff(midiNote);
      } catch (_) {}
    }
  }

  /// Stops all active voices immediately.
  Future<void> stopAll() async {
    _pressedKeys.clear();
    _activeVoices.clear();
    if (_player != null) {
      await _player!.stopMixerOutput();
    }
  }

  /// Updates audio FFT data every frame. Extracts the 15 to 180 frequency bin range.
  /// Continuously shifts 2D history rows outward every frame so expanding wave ripples
  /// continue marching all the way to the edge of the sea plane even after sound finishes.
  void updateFft([double dt = 0.016]) {
    if (!_isInitialized || _audioData == null) return;

    try {
      _audioData!.updateSamples();
      final data = _audioData!.getAudioData();

      // 1. Shift all 256 rows forward by 1 row (row 0..254 -> row 1..255)
      // This drives the continuous physical outward propagation of water ripples
      _historyTexture.setRange(512, 256 * 512, _historyTexture, 0);

      // 2. Insert new live audio frame at row 0
      if (data.isNotEmpty) {
        final copyLen = math.min(512, data.length);
        _historyTexture.setRange(0, copyLen, data, 0);
        if (copyLen < 512) {
          _historyTexture.fillRange(copyLen, 512, 0.0);
        }

        const startBin = 15;
        const endBin = 180;
        const count = endBin - startBin + 1; // 166

        for (var i = 0; i < count; i++) {
          final binIndex = startBin + i;
          final rawVal = binIndex < data.length
              ? data[binIndex].clamp(0.0, 1.0)
              : 0.0;
          _fftBuffer[i] = rawVal;
          // Exponential smoothing for HUD bar visualizer
          _smoothedFft[i] = _smoothedFft[i] * 0.60 + rawVal * 0.40;
          if (_smoothedFft[i] < 0.01) _smoothedFft[i] = 0.0;
        }
      } else {
        // No new audio incoming: insert silence at row 0 (center) while existing ripples march outward
        _historyTexture.fillRange(0, 512, 0.0);
        for (var i = 0; i < _smoothedFft.length; i++) {
          _smoothedFft[i] = 0.0;
        }
      }
    } catch (e) {
      // Audio stream may be pausing or resetting
    }
  }

  void dispose() {
    _audioData?.dispose();
    _player?.dispose();
    if (SoLoud.instance.isInitialized) {
      SoLoud.instance.deinit();
    }
    _isInitialized = false;
  }
}
