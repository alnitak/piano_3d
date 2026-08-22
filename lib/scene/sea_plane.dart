import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-detail 256x256 double-sided triangulated mesh plane reacting to 2D texture FFT audio data.
/// Fresh incoming FFT values form a ring at 10% radius from sea center (increasing from 0° to 180°,
/// decreasing from 180° to 360°), expanding outwards over time to 100% of sea width while attenuating to 0.
class SeaPlane {
  static const int cols = 256;
  static const int rows = 256;
  static const int vertexCount = cols * rows;

  final double width;
  final double depth;
  final vm.Vector3 origin;

  late final Float32List _positions;
  late final Float32List _normals;
  late final Float32List _colors;
  late final Float32List _texCoords;
  late final Uint32List _indices;

  late final MeshGeometry _geometry;
  late final PhysicallyBasedMaterial _material;
  late final Node node;

  SeaPlane({this.width = 32.0, this.depth = 28.0, vm.Vector3? origin})
    : origin = origin ?? vm.Vector3(-16.0, -0.28, 0.65) {
    _initBuffers();
    _buildMesh();
  }

  void _initBuffers() {
    _positions = Float32List(vertexCount * 3);
    _normals = Float32List(vertexCount * 3);
    _colors = Float32List(vertexCount * 4);
    _texCoords = Float32List(vertexCount * 2);

    // Double-sided triangles: 2 top-facing triangles + 2 bottom-facing triangles per quad
    final quadCount = (cols - 1) * (rows - 1);
    final triangleCount = quadCount * 4;
    _indices = Uint32List(triangleCount * 3);

    // Initial base grid setup extending along +Z into background
    final dx = width / (cols - 1);
    final dz = depth / (rows - 1);

    var vIdx = 0;
    var tIdx = 0;

    for (var r = 0; r < rows; r++) {
      final z = origin.z + (r * dz);
      final v = r / (rows - 1);

      for (var c = 0; c < cols; c++) {
        final x = origin.x + (c * dx);
        final u = c / (cols - 1);

        final pIdx = vIdx * 3;
        _positions[pIdx] = x;
        _positions[pIdx + 1] = origin.y;
        _positions[pIdx + 2] = z;

        _normals[pIdx] = 0.0;
        _normals[pIdx + 1] = 1.0;
        _normals[pIdx + 2] = 0.0;

        final cIdx = vIdx * 4;
        _colors[cIdx] = 0.04;
        _colors[cIdx + 1] = 0.16;
        _colors[cIdx + 2] = 0.36;
        _colors[cIdx + 3] = 1.0;

        _texCoords[tIdx] = u;
        _texCoords[tIdx + 1] = v;
        tIdx += 2;

        vIdx++;
      }
    }

    // Generate double-sided triangles for each grid quad (using 32-bit indices)
    var iIdx = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final v00 = r * cols + c;
        final v10 = v00 + 1;
        final v01 = v00 + cols;
        final v11 = v01 + 1;

        // --- Front / Top Face (winding points up towards +Y) ---
        _indices[iIdx++] = v00;
        _indices[iIdx++] = v01;
        _indices[iIdx++] = v10;

        _indices[iIdx++] = v10;
        _indices[iIdx++] = v01;
        _indices[iIdx++] = v11;

        // --- Back / Bottom Face (reverse winding for double-sided rendering) ---
        _indices[iIdx++] = v00;
        _indices[iIdx++] = v10;
        _indices[iIdx++] = v01;

        _indices[iIdx++] = v10;
        _indices[iIdx++] = v11;
        _indices[iIdx++] = v01;
      }
    }
  }

  void _buildMesh() {
    _geometry = MeshGeometry.fromArrays(
      positions: _positions,
      normals: _normals,
      colors: _colors,
      texCoords: _texCoords,
      indices: _indices,
      storage: GeometryStorage.updatable,
    );

    // Procedural ocean water material with clearcoat gloss and vibrant color
    _material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.06, 0.32, 0.55, 1.0)
      ..roughnessFactor = 0.16
      ..metallicFactor = 0.08
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.06
      ..vertexColorWeight = 1.0;

    node = Node(name: 'SeaPlane', mesh: Mesh(_geometry, _material))
      ..castsShadows =
          false // Prevent self-shadowing acne/black spots on waving water surface
      ..raycastable = false;
  }

  /// Updates mesh vertices, normals, and vertex colors.
  /// Incoming audio FFT values form a ring at 10% radius from the sea center.
  /// Bins are mapped increasing from 0° to 180°, and decreasing from 180° to 360°.
  /// Over time, the ring expands outward to 100% of sea width and decreases to 0.
  void update(double time, Float32List fftData, [Float32List? texture2dData]) {
    final dx = width / (cols - 1);
    final dz = depth / (rows - 1);

    // Center of the sea plane
    final centerX = origin.x + width / 2.0;
    final centerZ = origin.z + depth / 2.0;

    // 100% radius is half the sea width (from center to edge)
    final seaRadius = width / 2.0;
    final rStart = 0.10 * seaRadius; // 10% of sea width / radius
    final rEnd = seaRadius; // 100% of sea width

    final has2D = texture2dData != null && texture2dData.length >= 512;
    final fftLen = fftData.length;

    // Update positions and colors
    var vIdx = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = origin.x + (c * dx);
        final z = origin.z + (r * dz);

        // Distance and angle relative to sea plane center
        final relX = x - centerX;
        final relZ = z - centerZ;
        final dist = math.sqrt(relX * relX + relZ * relZ);

        // Calculate radial expansion progress s in [0, 1] and height attenuation
        double s = 0.0;
        double attenuation = 0.0;
        int texRow = 0;

        if (dist < rStart) {
          // Inside 10% inner radius: sample newest audio frame (row 0) with smooth center fade
          s = 0.0;
          final innerFade = rStart > 0 ? (dist / rStart).clamp(0.0, 1.0) : 1.0;
          attenuation = innerFade;
          texRow = 0;
        } else if (dist <= rEnd) {
          // Expanding zone (10% to 100%): map radial expansion to texture history rows
          s = (dist - rStart) / (rEnd - rStart);
          texRow = (s * 255.0).toInt().clamp(0, 255);
          // Height values decrease smoothly to 0 as circle reaches 100%
          attenuation = (1.0 - s);
        } else {
          // Beyond 100% of sea width: completely 0 height
          s = 1.0;
          attenuation = 0.0;
          texRow = 255;
        }

        // Angle around center [0, 2*pi]
        final angle = math.atan2(relZ, relX);
        final angleRad = angle < 0 ? (angle + 2.0 * math.pi) : angle;

        // 0° to 180°: increasing (0.0 -> 1.0)
        // 180° to 360°: decreasing (1.0 -> 0.0)
        final double t = angleRad <= math.pi
            ? angleRad / math.pi
            : (2.0 * math.pi - angleRad) / math.pi;

        // Map t in [0, 1] to FFT frequency bins in the 15..180 range
        final bin = (15 + (t * 165.0).toInt()).clamp(15, 180);

        double rawFft = 0.0;

        if (has2D) {
          final texIdx = texRow * 512 + bin;
          if (texIdx < texture2dData.length) {
            rawFft = texture2dData[texIdx];
          }
        } else if (fftLen > 0) {
          final fallbackBin = ((t * (fftLen - 1)).clamp(0, fftLen - 1)).toInt();
          rawFft = fftData[fallbackBin];
        }

        // Strict noise gate
        double fftVal = 0.0;
        if (rawFft >= 0.02) {
          fftVal = ((rawFft - 0.02) / 0.98 * 0.33).clamp(0.0, 1.0);
        }

        // Attenuated FFT wave ring height (starts at 10%, expands to 100%, drops to 0)
        final waveRing = fftVal * attenuation;

        // Concentric droplet ripples radiating outward
        final concentricCarrier = waveRing > 0.0
            ? math.sin(dist * 12.0 - time * 5.0) * (waveRing * 0.7)
            : 0.0;
        final concentricPulse = waveRing > 0.0 ? waveRing * 1.5 : 0.0;

        final fftDisplacement = concentricPulse + concentricCarrier;

        // Ambient natural ocean wave movement
        final ambient1 = math.sin(x * 0.45 + time * 1.6 + z * 0.2) * 0.18;
        final ambient2 = math.cos(z * 0.60 - time * 1.3 + x * 0.3) * 0.12;
        final ambient3 = math.sin((x * 0.8 + z * 0.8) + time * 2.2) * 0.06;
        final microRipple = math.sin(x * 2.5 + z * 2.5 + time * 3.8) * 0.02;

        final height =
            origin.y +
            ambient1 +
            ambient2 +
            ambient3 +
            microRipple +
            fftDisplacement;

        final pIdx = vIdx * 3;
        _positions[pIdx + 1] = height;

        // Dynamic vertex color shading: deep ocean sapphire in troughs, bright turquoise at expanding ripple crests
        final normalizedH = (height - origin.y + 0.25) / 1.4;
        final peakEnergy =
            (normalizedH.clamp(0.0, 1.0) * 0.65 + waveRing * 0.55).clamp(
              0.0,
              1.0,
            );

        final cIdx = vIdx * 4;
        _colors[cIdx] = 0.04 + peakEnergy * 0.28;
        _colors[cIdx + 1] = 0.16 + peakEnergy * 0.76;
        _colors[cIdx + 2] = 0.36 + peakEnergy * 0.62;
        _colors[cIdx + 3] = 1.0;

        vIdx++;
      }
    }

    // Recalculate smooth surface normals
    for (var r = 0; r < rows; r++) {
      final rPrev = (r - 1).clamp(0, rows - 1);
      final rNext = (r + 1).clamp(0, rows - 1);
      final rDist = (rNext - rPrev) * dz;

      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final pIdx = idx * 3;

        final cPrev = (c - 1).clamp(0, cols - 1);
        final cNext = (c + 1).clamp(0, cols - 1);
        final cDist = (cNext - cPrev) * dx;

        final leftIdx = (r * cols + cPrev) * 3;
        final rightIdx = (r * cols + cNext) * 3;
        final topIdx = (rPrev * cols + c) * 3;
        final bottomIdx = (rNext * cols + c) * 3;

        final hL = _positions[leftIdx + 1];
        final hR = _positions[rightIdx + 1];
        final hT = _positions[topIdx + 1];
        final hB = _positions[bottomIdx + 1];

        final nx = -(hR - hL) / (cDist > 0 ? cDist : 1.0);
        final nz = -(hB - hT) / (rDist > 0 ? rDist : 1.0);
        const ny = 1.0;

        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        _normals[pIdx] = nx / len;
        _normals[pIdx + 1] = ny / len;
        _normals[pIdx + 2] = nz / len;
      }
    }

    // Upload new buffer data to GPU
    _geometry.updatePositions(_positions);
    _geometry.updateNormals(_normals);
    _geometry.updateColors(_colors);
  }
}
