import 'dart:async';
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

  bool get isInitialized => _isInitialized;
  bool get isPreloaded => _isPreloaded;
  double get preloadProgress => _preloadProgress;
  String? get statusMessage => _statusMessage;
  SoundFontFile? get soundFont => _soundFont;
  SoundFontPlayer? get player => _player;
  List<Preset> get presets => _soundFont?.presets ?? [];
  Float32List get fftData => _smoothedFft;

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

      // Set sustain multiplier (sustain X) to 0.1 as specified in user request
      _player!.sustainMultiplier = 0.1;
      _player!.sustainTime = 0.1;

      // Initialize 2D texture audio data for FFT extraction
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
      targetPreset = availablePresets[index.clamp(0, availablePresets.length - 1)];
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
  void updateFft() {
    if (!_isInitialized || _audioData == null) return;

    try {
      _audioData!.updateSamples();
      final data = _audioData!.getAudioData();

      if (data.isNotEmpty) {
        // Texture format gives rows of 512 floats (first 256 are FFT, second 256 are Wave)
        // We take the current row's FFT bins from 15 to 180 (166 values)
        const startBin = 15;
        const endBin = 180;
        const count = endBin - startBin + 1; // 166

        for (var i = 0; i < count; i++) {
          final binIndex = startBin + i;
          final rawVal = binIndex < data.length ? data[binIndex].clamp(0.0, 1.0) : 0.0;
          _fftBuffer[i] = rawVal;
          // Exponential smoothing for fluid wave aesthetics
          _smoothedFft[i] = _smoothedFft[i] * 0.65 + rawVal * 0.35;
        }
      } else {
        // Decay to zero when quiet
        for (var i = 0; i < _smoothedFft.length; i++) {
          _smoothedFft[i] *= 0.90;
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
