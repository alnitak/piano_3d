import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'audio/audio_controller.dart';
import 'scene/camera_orbit_controller.dart';
import 'scene/piano_model.dart';
import 'scene/sea_plane.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Piano3DApp());
}

class Piano3DApp extends StatelessWidget {
  const Piano3DApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '3D Piano & FFT Sea',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF00D2FF),
        useMaterial3: true,
      ),
      home: const Piano3DSceneScreen(),
    );
  }
}

class Piano3DSceneScreen extends StatefulWidget {
  const Piano3DSceneScreen({super.key});

  @override
  State<Piano3DSceneScreen> createState() => _Piano3DSceneScreenState();
}

class _Piano3DSceneScreenState extends State<Piano3DSceneScreen>
    with SingleTickerProviderStateMixin {
  final Scene _scene = Scene();
  final AudioController _audio = AudioController.instance;
  late final CameraOrbitController _cameraController;

  late final PianoModel _piano;
  late final SeaPlane _seaPlane;

  bool _isSceneReady = false;
  double _elapsedTime = 0.0;

  // Active key interaction tracking
  int? _activePointerKeyMidi;
  bool _isOrbitDragging = false;
  Offset? _lastPointerPos;

  // Selected preset for soundfont playback
  int _selectedPresetIndex = 0;
  double _sustainMultiplier = 0.01;

  @override
  void initState() {
    super.initState();
    _cameraController = CameraOrbitController(
      target: vm.Vector3(0.0, 1.5, 0.20),
      yaw: 0.0,
      pitch: 0.44,
      distance: 2.2,
    );

    _initSceneAndAudio();
  }

  Future<void> _initSceneAndAudio() async {
    // 1. Initialize Flutter Scene static resources
    await Scene.initializeStaticResources();

    // 2. Build 3D models
    _piano = PianoModel();
    _seaPlane = SeaPlane(
      width: 8.0,
      depth: 8.0,
      origin: vm.Vector3(-4.0, -0.04, 0.65),
    );

    // 3. Assemble Scene graph
    _scene.add(_piano.rootNode);
    _scene.add(_seaPlane.node);

    // 4. Configure Sky Dome & Environment
    _scene.skybox = Skybox(
      GradientSkySource(
        zenithColor: vm.Vector3(0.06, 0.24, 0.68),
        horizonColor: vm.Vector3(0.38, 0.65, 0.92),
        groundColor: vm.Vector3(0.015, 0.06, 0.14),
        sunDirection: vm.Vector3(0.3, 0.6, 0.75).normalized(),
        sunColor: vm.Vector3(1.3, 1.15, 0.95),
        sunSharpness: 350.0,
      ),
      intensity: 1.2,
    );

    // 5. Directional sun lighting with real-time shadow cascades
    _scene.directionalLight = DirectionalLight(
      direction: vm.Vector3(-0.3, -0.6, -0.75).normalized(),
      intensity: 1.0,
      castsShadow: true,
      color: vm.Vector3(1.0, 0.96, 0.90),
      shadowDepthBias: 0.015,
      shadowNormalBias: 0.0002,
    );

    // 6. Post-processing stack (ACES tone mapping, Screen Space Reflections, Bloom, GTAO)
    _scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.08,
      bloomEnabled: true,
      bloomThreshold: 0.92,
      bloomIntensity: 0.22,
      bloomScatter: 0.72,
      ambientOcclusionEnabled: true,
      ambientOcclusionMethod: AmbientOcclusionMethod.obscurance,
      ambientOcclusionIntensity: 0.8,
      ambientOcclusionHalfResolution: true,
      screenSpaceReflectionsIntensity: 0.3,
      vignetteEnabled: true,
      vignetteIntensity: 0.32,
      vignetteRadius: 0.75,
    );

    if (mounted) {
      setState(() => _isSceneReady = true);
    }

    // 7. Initialize Audio engine & preload SoundFont
    await _audio.initialize(
      soundFontAsset: 'assets/SFX_StarWars_weapons.SF2',
      onProgress: (progress) {
        if (mounted) setState(() {});
      },
    );

    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  /// Per-frame animation tick callback driving the FFT wave deformation and key action.
  void _onFrameTick(Duration elapsed, double dt) {
    final clampedDt = dt.clamp(0.001, 0.1);
    _elapsedTime += clampedDt;

    // Update audio FFT data (bins 15-180)
    _audio.updateFft(clampedDt);

    // Deform 256x256 sea plane mesh with 2D texture concentric waves
    _seaPlane.update(_elapsedTime, _audio.fftData, _audio.texture2dData);

    // Animate piano keys spring action
    _piano.update(clampedDt);

    // Smooth camera orbit
    _cameraController.update(clampedDt);
  }

  /// Pointer interaction handling for piano keys and camera rotation.
  void _handlePointerDown(PointerDownEvent event, Size viewportSize) {
    _lastPointerPos = event.localPosition;

    // Raycast against the piano keybed plane
    final hitKey = _raycastPianoKey(event.localPosition, viewportSize);

    if (hitKey != null) {
      // Key pressed!
      _isOrbitDragging = false;
      _pressKey(hitKey);
    } else {
      // Orbit drag
      _isOrbitDragging = true;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, Size viewportSize) {
    if (_lastPointerPos == null) return;
    final delta = event.localPosition - _lastPointerPos!;
    _lastPointerPos = event.localPosition;

    if (_isOrbitDragging) {
      // Orbit camera
      _cameraController.rotate(delta.dx, delta.dy);
    } else {
      // Check for glissando / dragged key transition
      final hitKey = _raycastPianoKey(event.localPosition, viewportSize);
      if (hitKey != null && hitKey.midiNote != _activePointerKeyMidi) {
        _releaseActiveKey();
        _pressKey(hitKey);
      } else if (hitKey == null && _activePointerKeyMidi != null) {
        _releaseActiveKey();
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _isOrbitDragging = false;
    _lastPointerPos = null;
    _releaseActiveKey();
  }

  void _handlePointerScroll(PointerScrollEvent event) {
    _cameraController.zoom(event.scrollDelta.dy * 0.005);
  }

  void _pressKey(PianoKeyInfo key) {
    _activePointerKeyMidi = key.midiNote;
    _piano.setKeyPressed(key.midiNote, true);
    _audio.playNote(
      keyIndex: key.index,
      midiNote: key.midiNote,
      customPresetIndex: _selectedPresetIndex,
    );
    setState(() {});
  }

  void _releaseActiveKey() {
    if (_activePointerKeyMidi != null) {
      final midi = _activePointerKeyMidi!;
      _piano.setKeyPressed(midi, false);
      _audio.stopNote(midi);
      _activePointerKeyMidi = null;
      setState(() {});
    }
  }

  /// Casts a ray from screen space to the piano keys using engine raycast and analytical Ray-Box testing.
  PianoKeyInfo? _raycastPianoKey(Offset screenPos, Size viewportSize) {
    final camera = _cameraController.getCamera();
    final ray = camera.screenPointToRay(screenPos, viewportSize);

    // 1. Engine scene raycast
    final hit = _scene.raycast(ray);
    if (hit != null) {
      final key = _piano.getKeyForNode(hit.node);
      if (key != null) return key;
    }

    // 2. Analytical 3D Ray-Box intersection fallback
    return _piano.findKeyHitByRay(ray.origin, ray.direction);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSceneReady) {
      return Scaffold(
        backgroundColor: const Color(0xFF070B14),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF00D2FF)),
              const SizedBox(height: 20),
              Text(
                'Loading 3D Piano & Shaders...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF050811),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          return Stack(
            children: [
              // 1. 3D Scene View
              Positioned.fill(
                child: Listener(
                  onPointerDown: (e) => _handlePointerDown(e, viewportSize),
                  onPointerMove: (e) => _handlePointerMove(e, viewportSize),
                  onPointerUp: _handlePointerUp,
                  onPointerCancel: (_) => _releaseActiveKey(),
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent) _handlePointerScroll(e);
                  },
                  child: SceneView(
                    _scene,
                    cameraBuilder: (_) => _cameraController.getCamera(),
                    onTick: _onFrameTick,
                  ),
                ),
              ),

              // 2. Top Header HUD with preset controls & audio status
              Positioned(top: 24, left: 24, right: 24, child: _buildTopHud()),

              // 3. Bottom Controls & FFT Visualizer Bar
              Positioned(
                bottom: 24,
                left: 24,
                right: 24,
                child: _buildBottomHud(),
              ),

              // 4. Loading indicator while SoundFont preloads
              if (!_audio.isPreloaded && _audio.preloadProgress > 0)
                Positioned(
                  top: 90,
                  left: 24,
                  child: _buildPreloadProgressCard(),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopHud() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              // App Title & Badge
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D2FF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.piano,
                  color: Color(0xFF00D2FF),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '3D PIANO • AUDIO FFT SEA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    _audio.statusMessage ?? 'SFX Star Wars Weapons SoundFont',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // SoundFont Selector Dropdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _audio.currentSoundFontAsset,
                    dropdownColor: const Color(0xFF1E293B),
                    icon: const Icon(
                      Icons.music_note,
                      color: Color(0xFF00D2FF),
                      size: 16,
                    ),
                    items: AudioController.availableSoundFonts.map((sf) {
                      final name = sf.split('/').last;
                      return DropdownMenuItem<String>(
                        value: sf,
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) async {
                      if (val != null && val != _audio.currentSoundFontAsset) {
                        await _audio.loadSoundFont(
                          val,
                          onProgress: (p) => setState(() {}),
                        );
                        setState(() {
                          _selectedPresetIndex = 0;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Preset Selector Dropdown
              if (_audio.presets.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _selectedPresetIndex < _audio.presets.length
                          ? _selectedPresetIndex
                          : 0,
                      dropdownColor: const Color(0xFF1E293B),
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF00D2FF),
                      ),
                      items: List.generate(_audio.presets.length, (i) {
                        final p = _audio.presets[i];
                        return DropdownMenuItem<int>(
                          value: i,
                          child: Text(
                            'Preset ${p.program}: ${p.name}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedPresetIndex = val);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],

              // Camera Reset Button
              IconButton.filledTonal(
                tooltip: 'Reset Camera View',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                ),
                onPressed: () {
                  setState(() => _cameraController.reset());
                },
                icon: const Icon(
                  Icons.center_focus_strong,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomHud() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              // Real-time Mini FFT Waveform Graphic
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 36,
                  child: CustomPaint(
                    painter: FftWavePainter(fftData: _audio.fftData),
                  ),
                ),
              ),
              const SizedBox(width: 24),

              // Sustain X Control
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sustain X: ${_sustainMultiplier.toStringAsFixed(2)}x',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                      ),
                      child: Slider(
                        value: _sustainMultiplier,
                        min: 0.01,
                        max: 2.0,
                        activeColor: const Color(0xFF00D2FF),
                        onChanged: (val) {
                          setState(() {
                            _sustainMultiplier = val;
                            _audio.player?.sustainMultiplier = val;
                            _audio.player?.sustainTime = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),

              // Piano Keys hint
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app,
                      size: 14,
                      color: Color(0xFF00D2FF),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Drag keys to play • Drag sea to orbit',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreloadProgressCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  value: _audio.preloadProgress,
                  strokeWidth: 2.5,
                  color: const Color(0xFF00D2FF),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Preloading Samples: ${(_audio.preloadProgress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a real-time glowing audio FFT visualizer bar chart in the HUD.
class FftWavePainter extends CustomPainter {
  final Float32List fftData;

  FftWavePainter({required this.fftData});

  @override
  void paint(Canvas canvas, Size size) {
    if (fftData.isEmpty) return;

    final barCount = 48;
    final step = fftData.length / barCount;
    final barWidth = (size.width / barCount) * 0.75;
    final gap = (size.width / barCount) * 0.25;

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      final sampleIdx = (i * step).toInt().clamp(0, fftData.length - 1);
      final value = fftData[sampleIdx].clamp(0.0, 1.0);

      final x = i * (barWidth + gap);
      final h = (value * size.height).clamp(2.0, size.height);
      final y = size.height - h;

      // Color gradient from cyan to electric blue
      final ratio = i / barCount;
      paint.color = Color.lerp(
        const Color(0xFF00E5FF),
        const Color(0xFF7000FF),
        ratio,
      )!.withValues(alpha: 0.4 + value * 0.6);

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant FftWavePainter oldDelegate) => true;
}
