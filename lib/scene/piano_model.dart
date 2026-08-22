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
    final halfW = width / 2.0 + 0.008; // hit tolerance padding
    final halfH = height / 2.0 + 0.015;
    final halfL = length / 2.0 + 0.008;

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

/// 3D Model of a 2-octave piano keyboard (half-size, elevated by half width) with polished materials.
class PianoModel {
  final Node rootNode = Node(name: 'PianoRoot');
  final List<PianoKeyInfo> keys = [];
  final Map<Node, PianoKeyInfo> _nodeToKey = {};

  // Half-size Key dimensions
  static const double whiteKeyWidth = 0.11;
  static const double whiteKeyLength = 0.56;
  static const double whiteKeyHeight = 0.065;
  static const double whiteKeyGap = 0.004;

  static const double blackKeyWidth = 0.06;
  static const double blackKeyLength = 0.34;
  static const double blackKeyHeight = 0.075;

  static const int startMidi = 48; // C3
  static const int totalKeys = 25; // C3 to C5 (2 octaves)

  late final double totalWidth;
  late final double baseY;

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
    // Soft satin ivory white key material (non-glare)
    _whiteKeyMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.92, 0.92, 0.90, 1.0)
      ..roughnessFactor = 0.45
      ..metallicFactor = 0.0
      ..specular = 0.45
      ..clearcoat = 0.0;

    // Deep ebony black key material (true black, low reflection)
    _blackKeyMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.004, 0.004, 0.004, 1.0)
      ..roughnessFactor = 0.55
      ..metallicFactor = 0.0
      ..specular = 0.35
      ..clearcoat = 0.0;

    // Deep satin black piano body casing (true black, low glare)
    _pianoCaseMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.003, 0.003, 0.003, 1.0)
      ..roughnessFactor = 0.60
      ..metallicFactor = 0.0
      ..specular = 0.30
      ..clearcoat = 0.0;

    // Warm brushed brass/gold trim
    _goldTrimMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.90, 0.75, 0.30, 1.0)
      ..roughnessFactor = 0.40
      ..metallicFactor = 0.85
      ..clearcoat = 0.0;

    // Red velvet damper felt strip
    _redFeltMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.70, 0.04, 0.10, 1.0)
      ..roughnessFactor = 0.95
      ..metallicFactor = 0.0;
  }

  void _buildPiano() {
    final noteNames = [
      'C',
      'C#',
      'D',
      'D#',
      'E',
      'F',
      'F#',
      'G',
      'G#',
      'A',
      'A#',
      'B',
    ];
    final isBlackPattern = [
      false,
      true,
      false,
      true,
      false,
      false,
      true,
      false,
      true,
      false,
      true,
      false,
    ];

    // Shared key meshes
    final whiteGeometry = CuboidGeometry(
      vm.Vector3(whiteKeyWidth, whiteKeyHeight, whiteKeyLength),
    );
    final blackGeometry = CuboidGeometry(
      vm.Vector3(blackKeyWidth, blackKeyHeight, blackKeyLength),
    );

    // Calculate total white keys to center keyboard at X = 0
    var whiteCount = 0;
    for (var i = 0; i < totalKeys; i++) {
      final semitone = i % 12;
      if (!isBlackPattern[semitone]) whiteCount++;
    }

    totalWidth = whiteCount * (whiteKeyWidth + whiteKeyGap);
    // Position upper by half of the keyboard width
    baseY = totalWidth / 2.0;

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
        y = baseY;
        z = 0.20; // centered in Z
        w = whiteKeyWidth;
        l = whiteKeyLength;
        h = whiteKeyHeight;
        mesh = Mesh(whiteGeometry, _whiteKeyMaterial);

        lastWhiteX = currentWhiteX;
        currentWhiteX += whiteKeyWidth + whiteKeyGap;
      } else {
        // Position black key offset between neighboring white keys, elevated and pushed towards back (+Z)
        x = lastWhiteX + (whiteKeyWidth + whiteKeyGap) / 2.0;
        y = baseY + 0.022;
        z = 0.31;
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
    final casingWidth = keyboardWidth + 0.225;
    const centerZ = 0.20;

    // Key bed bottom foundation
    final bedGeo = CuboidGeometry(
      vm.Vector3(casingWidth, 0.08, whiteKeyLength + 0.175),
    );
    final bedNode =
        Node(name: 'PianoBed', mesh: Mesh(bedGeo, _pianoCaseMaterial))
          ..position = vm.Vector3(0.0, baseY - 0.06, centerZ + 0.025)
          ..raycastable = false;
    rootNode.add(bedNode);

    // Left cheek block
    final cheekGeo = CuboidGeometry(
      vm.Vector3(0.09, 0.14, whiteKeyLength + 0.175),
    );
    final leftCheek =
        Node(name: 'LeftCheek', mesh: Mesh(cheekGeo, _pianoCaseMaterial))
          ..position = vm.Vector3(
            -keyboardWidth / 2.0 - 0.055,
            baseY + 0.01,
            centerZ + 0.025,
          )
          ..raycastable = false;
    rootNode.add(leftCheek);

    // Right cheek block
    final rightCheek =
        Node(name: 'RightCheek', mesh: Mesh(cheekGeo, _pianoCaseMaterial))
          ..position = vm.Vector3(
            keyboardWidth / 2.0 + 0.055,
            baseY + 0.01,
            centerZ + 0.025,
          )
          ..raycastable = false;
    rootNode.add(rightCheek);

    // Rear fallboard / back rest (at the back of keys, +Z)
    final fallboardGeo = CuboidGeometry(
      vm.Vector3(keyboardWidth + 0.025, 0.225, 0.075),
    );
    final fallboard =
        Node(name: 'Fallboard', mesh: Mesh(fallboardGeo, _pianoCaseMaterial))
          ..position = vm.Vector3(
            0.0,
            baseY + 0.09,
            centerZ + whiteKeyLength / 2.0 + 0.04,
          )
          ..raycastable = false;
    rootNode.add(fallboard);

    // Red velvet felt strip along the fallboard
    final feltGeo = CuboidGeometry(
      vm.Vector3(keyboardWidth + 0.01, 0.02, 0.025),
    );
    final felt = Node(name: 'RedFelt', mesh: Mesh(feltGeo, _redFeltMaterial))
      ..position = vm.Vector3(
        0.0,
        baseY + 0.04,
        centerZ + whiteKeyLength / 2.0 + 0.005,
      )
      ..raycastable = false;
    rootNode.add(felt);

    // Gold brass accent lip
    final goldLipGeo = CuboidGeometry(
      vm.Vector3(keyboardWidth + 0.025, 0.01, 0.015),
    );
    final goldLip =
        Node(name: 'GoldAccent', mesh: Mesh(goldLipGeo, _goldTrimMaterial))
          ..position = vm.Vector3(
            0.0,
            baseY + 0.19,
            centerZ + whiteKeyLength / 2.0 + 0.005,
          )
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
      key.currentDepression +=
          (target - key.currentDepression) * math.min(1.0, dt * 28.0);

      // Key depression action: dip front down by rotating around rear edge and translating down
      final dipAngle = -key.currentDepression * 0.050; // radians
      final dipY = -key.currentDepression * 0.018;

      final rot = vm.Quaternion.axisAngle(vm.Vector3(1, 1, 0), dipAngle);
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
