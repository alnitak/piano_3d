import 'dart:math' as math;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Definition of a single piano key with geometry, notes, and animation state.
class PianoKeyInfo {
  final int index; // 0..24
  final int midiNote; // e.g. 48..72
  final String noteName; // e.g. "C3", "C#3"
  final bool isBlack;
  final double xPos;
  final double yPos;
  final double zPos;
  final double width;
  final double length;
  final double height;

  late final Node node;
  late final vm.Vector3 restPosition;
  late final vm.Quaternion restRotation;

  bool isPressed = false;
  double currentDepression = 0.0; // 0.0 to 1.0

  PianoKeyInfo({
    required this.index,
    required this.midiNote,
    required this.noteName,
    required this.isBlack,
    required this.xPos,
    required this.yPos,
    required this.zPos,
    required this.width,
    required this.length,
    required this.height,
  });

  /// Checks if a 3D ray intersects this key's bounding box. Returns distance t or null.
  double? intersectRay(vm.Vector3 rayOrigin, vm.Vector3 rayDir) {
    final halfW = width / 2.0 + 0.015; // hit tolerance padding
    final halfH = height / 2.0 + 0.03;
    final halfL = length / 2.0 + 0.015;

    final minX = xPos - halfW;
    final maxX = xPos + halfW;
    final minY = yPos - halfH;
    final maxY = yPos + halfH;
    final minZ = zPos - halfL;
    final maxZ = zPos + halfL;

    double tMin = -double.infinity;
    double tMax = double.infinity;

    // X axis slab
    if (rayDir.x.abs() > 1e-7) {
      var t1 = (minX - rayOrigin.x) / rayDir.x;
      var t2 = (maxX - rayOrigin.x) / rayDir.x;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tMin = math.max(tMin, t1);
      tMax = math.min(tMax, t2);
      if (tMin > tMax) return null;
    } else if (rayOrigin.x < minX || rayOrigin.x > maxX) {
      return null;
    }

    // Y axis slab
    if (rayDir.y.abs() > 1e-7) {
      var t1 = (minY - rayOrigin.y) / rayDir.y;
      var t2 = (maxY - rayOrigin.y) / rayDir.y;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tMin = math.max(tMin, t1);
      tMax = math.min(tMax, t2);
      if (tMin > tMax) return null;
    } else if (rayOrigin.y < minY || rayOrigin.y > maxY) {
      return null;
    }

    // Z axis slab
    if (rayDir.z.abs() > 1e-7) {
      var t1 = (minZ - rayOrigin.z) / rayDir.z;
      var t2 = (maxZ - rayOrigin.z) / rayDir.z;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
      }
      tMin = math.max(tMin, t1);
      tMax = math.min(tMax, t2);
      if (tMin > tMax) return null;
    } else if (rayOrigin.z < minZ || rayOrigin.z > maxZ) {
      return null;
    }

    if (tMax < 0) return null;
    return tMin > 0 ? tMin : tMax;
  }
}

/// 3D Model of a 2-octave piano keyboard with polished materials, specularity, and interactive keys.
class PianoModel {
  final Node rootNode = Node(name: 'PianoRoot');
  final List<PianoKeyInfo> keys = [];
  final Map<Node, PianoKeyInfo> _nodeToKey = {};

  // Key dimensions
  static const double whiteKeyWidth = 0.22;
  static const double whiteKeyLength = 1.12;
  static const double whiteKeyHeight = 0.13;
  static const double whiteKeyGap = 0.008;

  static const double blackKeyWidth = 0.12;
  static const double blackKeyLength = 0.68;
  static const double blackKeyHeight = 0.15;

  static const int startMidi = 48; // C3
  static const int totalKeys = 25; // C3 to C5 (2 octaves)

  late final PhysicallyBasedMaterial _whiteKeyMaterial;
  late final PhysicallyBasedMaterial _blackKeyMaterial;
  late final PhysicallyBasedMaterial _pianoCaseMaterial;
  late final PhysicallyBasedMaterial _goldTrimMaterial;
  late final PhysicallyBasedMaterial _redFeltMaterial;

  PianoModel() {
    _initMaterials();
    _buildPiano();
  }

  PianoKeyInfo? getKeyForNode(Node node) => _nodeToKey[node];

  void _initMaterials() {
    // High-gloss polished ivory white key material
    _whiteKeyMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.97, 0.97, 0.96, 1.0)
      ..roughnessFactor = 0.06
      ..metallicFactor = 0.02
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.04;

    // High-gloss ebony black key material
    _blackKeyMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.04, 0.04, 0.04, 1.0)
      ..roughnessFactor = 0.10
      ..metallicFactor = 0.18
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.06;

    // Polished grand piano black lacquer body
    _pianoCaseMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.02, 0.02, 0.02, 1.0)
      ..roughnessFactor = 0.08
      ..metallicFactor = 0.35
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.05;

    // Polished gold brass trim
    _goldTrimMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.95, 0.80, 0.35, 1.0)
      ..roughnessFactor = 0.15
      ..metallicFactor = 0.92
      ..clearcoat = 0.8;

    // Red velvet damper felt strip
    _redFeltMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.75, 0.05, 0.12, 1.0)
      ..roughnessFactor = 0.92
      ..metallicFactor = 0.0;
  }

  void _buildPiano() {
    final noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final isBlackPattern = [false, true, false, true, false, false, true, false, true, false, true, false];

    // Shared key meshes
    final whiteGeometry = CuboidGeometry(vm.Vector3(whiteKeyWidth, whiteKeyHeight, whiteKeyLength));
    final blackGeometry = CuboidGeometry(vm.Vector3(blackKeyWidth, blackKeyHeight, blackKeyLength));

    // Calculate total white keys to center keyboard at X = 0
    var whiteCount = 0;
    for (var i = 0; i < totalKeys; i++) {
      final semitone = i % 12;
      if (!isBlackPattern[semitone]) whiteCount++;
    }

    final totalWidth = whiteCount * (whiteKeyWidth + whiteKeyGap);
    final startX = -totalWidth / 2.0 + whiteKeyWidth / 2.0;

    double currentWhiteX = startX;
    double lastWhiteX = startX;

    for (var i = 0; i < totalKeys; i++) {
      final midi = startMidi + i;
      final octave = (midi ~/ 12) - 1;
      final semitone = i % 12;
      final isBlack = isBlackPattern[semitone];
      final name = '${noteNames[semitone]}$octave';

      double x, y, z, w, l, h;
      Mesh mesh;

      if (!isBlack) {
        x = currentWhiteX;
        y = 0.0;
        z = 0.40; // centered in Z
        w = whiteKeyWidth;
        l = whiteKeyLength;
        h = whiteKeyHeight;
        mesh = Mesh(whiteGeometry, _whiteKeyMaterial);

        lastWhiteX = currentWhiteX;
        currentWhiteX += whiteKeyWidth + whiteKeyGap;
      } else {
        // Position black key offset between neighboring white keys, elevated and pushed towards back (+Z)
        x = lastWhiteX + (whiteKeyWidth + whiteKeyGap) / 2.0;
        y = 0.045;
        z = 0.62;
        w = blackKeyWidth;
        l = blackKeyLength;
        h = blackKeyHeight;
        mesh = Mesh(blackGeometry, _blackKeyMaterial);
      }

      final keyInfo = PianoKeyInfo(
        index: i,
        midiNote: midi,
        noteName: name,
        isBlack: isBlack,
        xPos: x,
        yPos: y,
        zPos: z,
        width: w,
        length: l,
        height: h,
      );

      final keyNode = Node(name: 'Key_$name', mesh: mesh);
      keyNode.position = vm.Vector3(x, y, z);
      keyNode.raycastable = true;
      keyInfo.node = keyNode;
      keyInfo.restPosition = vm.Vector3(x, y, z);
      keyInfo.restRotation = vm.Quaternion.identity();

      keys.add(keyInfo);
      _nodeToKey[keyNode] = keyInfo;
      rootNode.add(keyNode);
    }

    _buildPianoCasing(totalWidth);
  }

  void _buildPianoCasing(double keyboardWidth) {
    final casingWidth = keyboardWidth + 0.45;
    const centerZ = 0.40;

    // Key bed bottom foundation
    final bedGeo = CuboidGeometry(vm.Vector3(casingWidth, 0.16, whiteKeyLength + 0.35));
    final bedNode = Node(
      name: 'PianoBed',
      mesh: Mesh(bedGeo, _pianoCaseMaterial),
    )
      ..position = vm.Vector3(0.0, -0.12, centerZ + 0.05)
      ..raycastable = false;
    rootNode.add(bedNode);

    // Left cheek block
    final cheekGeo = CuboidGeometry(vm.Vector3(0.18, 0.28, whiteKeyLength + 0.35));
    final leftCheek = Node(
      name: 'LeftCheek',
      mesh: Mesh(cheekGeo, _pianoCaseMaterial),
    )
      ..position = vm.Vector3(-keyboardWidth / 2.0 - 0.11, 0.02, centerZ + 0.05)
      ..raycastable = false;
    rootNode.add(leftCheek);

    // Right cheek block
    final rightCheek = Node(
      name: 'RightCheek',
      mesh: Mesh(cheekGeo, _pianoCaseMaterial),
    )
      ..position = vm.Vector3(keyboardWidth / 2.0 + 0.11, 0.02, centerZ + 0.05)
      ..raycastable = false;
    rootNode.add(rightCheek);

    // Rear fallboard / back rest (at the back of keys, +Z)
    final fallboardGeo = CuboidGeometry(vm.Vector3(keyboardWidth + 0.05, 0.45, 0.15));
    final fallboard = Node(
      name: 'Fallboard',
      mesh: Mesh(fallboardGeo, _pianoCaseMaterial),
    )
      ..position = vm.Vector3(0.0, 0.18, centerZ + whiteKeyLength / 2.0 + 0.08)
      ..raycastable = false;
    rootNode.add(fallboard);

    // Red velvet felt strip along the fallboard
    final feltGeo = CuboidGeometry(vm.Vector3(keyboardWidth + 0.02, 0.04, 0.05));
    final felt = Node(
      name: 'RedFelt',
      mesh: Mesh(feltGeo, _redFeltMaterial),
    )
      ..position = vm.Vector3(0.0, 0.08, centerZ + whiteKeyLength / 2.0 + 0.01)
      ..raycastable = false;
    rootNode.add(felt);

    // Gold brass accent lip
    final goldLipGeo = CuboidGeometry(vm.Vector3(keyboardWidth + 0.05, 0.02, 0.03));
    final goldLip = Node(
      name: 'GoldAccent',
      mesh: Mesh(goldLipGeo, _goldTrimMaterial),
    )
      ..position = vm.Vector3(0.0, 0.38, centerZ + whiteKeyLength / 2.0 + 0.01)
      ..raycastable = false;
    rootNode.add(goldLip);
  }

  /// Sets the pressed state for a specific key.
  void setKeyPressed(int midiNote, bool pressed) {
    for (final key in keys) {
      if (key.midiNote == midiNote) {
        key.isPressed = pressed;
        break;
      }
    }
  }

  /// Updates key depression animations per frame.
  void update(double dt) {
    for (final key in keys) {
      final target = key.isPressed ? 1.0 : 0.0;
      // Spring lerp towards target
      key.currentDepression += (target - key.currentDepression) * math.min(1.0, dt * 28.0);

      // Key depression action: dip front down by rotating around rear edge and translating down
      final dipAngle = -key.currentDepression * 0.050; // radians
      final dipY = -key.currentDepression * 0.035;

      final rot = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), dipAngle);
      key.node.rotation = rot;
      key.node.position = vm.Vector3(
        key.restPosition.x,
        key.restPosition.y + dipY,
        key.restPosition.z,
      );
    }
  }

  /// Finds the key clicked given a world-space ray. Black keys are checked first.
  PianoKeyInfo? findKeyHitByRay(vm.Vector3 rayOrigin, vm.Vector3 rayDir) {
    PianoKeyInfo? closestKey;
    double closestT = double.infinity;

    // Check black keys first (they sit above and closer to user's finger on upper section)
    for (final key in keys) {
      if (!key.isBlack) continue;
      final t = key.intersectRay(rayOrigin, rayDir);
      if (t != null && t < closestT) {
        closestT = t;
        closestKey = key;
      }
    }

    if (closestKey != null) return closestKey;

    // Check white keys
    for (final key in keys) {
      if (key.isBlack) continue;
      final t = key.intersectRay(rayOrigin, rayDir);
      if (t != null && t < closestT) {
        closestT = t;
        closestKey = key;
      }
    }

    return closestKey;
  }
}
