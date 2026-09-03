import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-detail triangulated mesh plane reacting to 2D texture FFT audio data.
/// Fresh incoming FFT values form a ring at 10% radius from sea center (increasing from 0° to 180°,
/// decreasing from 180° to 360°), expanding outwards over time to 100% of sea width while attenuating to 0.
class SeaPlane {
  static final int defaultCols = kIsWeb ? 128 : 256;
  static final int defaultRows = kIsWeb ? 128 : 256;

  final int cols;
  final int rows;
  final int vertexCount;

  final double width;
  final double depth;
  final vm.Vector3 origin;

  late final Float32List _positions;
  late final Float32List _normals;
  late final Float32List _colors;
  late final Float32List _texCoords;
  late final Uint32List _indices;

  // Precomputed static geometry data to eliminate per-frame math & allocations
  late final Float32List _baseX;
  late final Float32List _baseZ;
  late final Float32List _distances;
  late final Float32List _attenuations;
  late final Int32List _texIndices;
  late final Int32List _fallbackBins;

  late final MeshGeometry _geometry;
  late final PhysicallyBasedMaterial _material;
  late final Node node;

  SeaPlane({
    this.width = 32.0,
    this.depth = 28.0,
    vm.Vector3? origin,
    int? cols,
    int? rows,
  })  : cols = cols ?? defaultCols,
        rows = rows ?? defaultRows,
        vertexCount = (cols ?? defaultCols) * (rows ?? defaultRows),
        origin = origin ?? vm.Vector3(-16.0, -0.28, 0.65) {
    _initBuffers();
    _buildMesh();
  }

  void _initBuffers() {
    _positions = Float32List(vertexCount * 3);
    _normals = Float32List(vertexCount * 3);
    _colors = Float32List(vertexCount * 4);
    _texCoords = Float32List(vertexCount * 2);

    _baseX = Float32List(vertexCount);
    _baseZ = Float32List(vertexCount);
    _distances = Float32List(vertexCount);
    _attenuations = Float32List(vertexCount);
    _texIndices = Int32List(vertexCount);
    _fallbackBins = Int32List(vertexCount);

    // Single-sided top-facing triangles (camera is clamped above the water surface)
    final quadCount = (cols - 1) * (rows - 1);
    final triangleCount = quadCount * 2;
    _indices = Uint32List(triangleCount * 3);

    final dx = width / (cols - 1);
    final dz = depth / (rows - 1);

    final centerX = origin.x + width / 2.0;
    final centerZ = origin.z + depth / 2.0;

    final seaRadius = width / 2.0;
    final rStart = 0.10 * seaRadius;
    final rEnd = seaRadius;

    var vIdx = 0;
    var tIdx = 0;

    for (var r = 0; r < rows; r++) {
      final z = origin.z + (r * dz);
      final v = r / (rows - 1);
      final relZ = z - centerZ;

      for (var c = 0; c < cols; c++) {
        final x = origin.x + (c * dx);
        final u = c / (cols - 1);
        final relX = x - centerX;

        final dist = math.sqrt(relX * relX + relZ * relZ);

        _baseX[vIdx] = x;
        _baseZ[vIdx] = z;
        _distances[vIdx] = dist;

        double s = 0.0;
        double attenuation = 0.0;
        int texRow = 0;

        if (dist < rStart) {
          s = 0.0;
          final innerFade = rStart > 0 ? (dist / rStart).clamp(0.0, 1.0) : 1.0;
          attenuation = innerFade;
          texRow = 0;
        } else if (dist <= rEnd) {
          s = (dist - rStart) / (rEnd - rStart);
          texRow = (s * 255.0).toInt().clamp(0, 255);
          attenuation = 1.0 - s;
        } else {
          s = 1.0;
          attenuation = 0.0;
          texRow = 255;
        }
        _attenuations[vIdx] = attenuation;

        final angle = math.atan2(relZ, relX);
        final angleRad = angle < 0 ? (angle + 2.0 * math.pi) : angle;
        final double t = angleRad <= math.pi
            ? angleRad / math.pi
            : (2.0 * math.pi - angleRad) / math.pi;

        final bin = (15 + (t * 165.0).toInt()).clamp(15, 180);
        _texIndices[vIdx] = texRow * 512 + bin;
        _fallbackBins[vIdx] = (t * 165.0).toInt().clamp(0, 165);

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

    // Generate single-sided top-facing triangles (winding CCW points up towards +Y)
    var iIdx = 0;
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final v00 = r * cols + c;
        final v10 = v00 + 1;
        final v01 = v00 + cols;
        final v11 = v01 + 1;

        _indices[iIdx++] = v00;
        _indices[iIdx++] = v01;
        _indices[iIdx++] = v10;

        _indices[iIdx++] = v10;
        _indices[iIdx++] = v01;
        _indices[iIdx++] = v11;
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
      ..castsShadows = false
      ..raycastable = false;
  }

  /// Updates mesh vertices, normals, and vertex colors using precomputed static tables.
  void update(double time, Float32List fftData, [Float32List? texture2dData]) {
    final dx = width / (cols - 1);
    final dz = depth / (rows - 1);

    final has2D = texture2dData != null && texture2dData.length >= 512;
    final fftLen = fftData.length;

    final timePhase1 = time * 1.6;
    final timePhase2 = -time * 1.3;
    final timePhase3 = time * 2.2;
    final timePhase4 = time * 3.8;
    final timeCarrier = -time * 5.0;

    final origY = origin.y;

    for (var vIdx = 0; vIdx < vertexCount; vIdx++) {
      final attenuation = _attenuations[vIdx];
      final dist = _distances[vIdx];
      final x = _baseX[vIdx];
      final z = _baseZ[vIdx];

      double rawFft = 0.0;
      if (has2D) {
        final texIdx = _texIndices[vIdx];
        if (texIdx < texture2dData.length) {
          rawFft = texture2dData[texIdx];
        }
      } else if (fftLen > 0) {
        final fallbackBin = _fallbackBins[vIdx].clamp(0, fftLen - 1);
        rawFft = fftData[fallbackBin];
      }

      double fftVal = 0.0;
      if (rawFft >= 0.02) {
        fftVal = ((rawFft - 0.02) / 0.98 * 0.33).clamp(0.0, 1.0);
      }

      final waveRing = fftVal * attenuation;

      final concentricCarrier = waveRing > 0.0
          ? math.sin(dist * 12.0 + timeCarrier) * (waveRing * 0.7)
          : 0.0;
      final concentricPulse = waveRing > 0.0 ? waveRing * 5.0 : 0.0;
      final fftDisplacement = concentricPulse + concentricCarrier;

      final ambient1 = math.sin(x * 0.45 + z * 0.2 + timePhase1) * 0.18;
      final ambient2 = math.cos(z * 0.60 + x * 0.3 + timePhase2) * 0.12;
      final ambient3 = math.sin((x * 0.8 + z * 0.8) + timePhase3) * 0.06;
      final microRipple = math.sin(x * 2.5 + z * 2.5 + timePhase4) * 0.02;

      final height =
          origY +
          ambient1 +
          ambient2 +
          ambient3 +
          microRipple +
          fftDisplacement;

      final pIdx = vIdx * 3;
      _positions[pIdx + 1] = height;

      final normalizedH = (height - origY + 0.25) / 1.4;
      final peakEnergy =
          (normalizedH.clamp(0.0, 1.0) * 0.65 + waveRing * 0.55).clamp(
            0.0,
            1.0,
          );

      final cIdx = vIdx * 4;
      _colors[cIdx] = 0.04 + peakEnergy * 0.28;
      _colors[cIdx + 1] = 0.16 + peakEnergy * 0.76;
      _colors[cIdx + 2] = 0.36 + peakEnergy * 0.62;
    }

    // Recalculate smooth surface normals
    for (var r = 0; r < rows; r++) {
      final rPrev = (r - 1).clamp(0, rows - 1);
      final rNext = (r + 1).clamp(0, rows - 1);
      final invRDist = 1.0 / ((rNext - rPrev) * dz);

      final rowOffset = r * cols;
      final topRowOffset = rPrev * cols;
      final bottomRowOffset = rNext * cols;

      for (var c = 0; c < cols; c++) {
        final cPrev = (c - 1).clamp(0, cols - 1);
        final cNext = (c + 1).clamp(0, cols - 1);
        final invCDist = 1.0 / ((cNext - cPrev) * dx);

        final pIdx = (rowOffset + c) * 3;
        final leftIdx = (rowOffset + cPrev) * 3 + 1;
        final rightIdx = (rowOffset + cNext) * 3 + 1;
        final topIdx = (topRowOffset + c) * 3 + 1;
        final bottomIdx = (bottomRowOffset + c) * 3 + 1;

        final hL = _positions[leftIdx];
        final hR = _positions[rightIdx];
        final hT = _positions[topIdx];
        final hB = _positions[bottomIdx];

        final nx = -(hR - hL) * invCDist;
        final nz = -(hB - hT) * invRDist;
        const ny = 1.0;

        final len = math.sqrt(nx * nx + 1.0 + nz * nz);
        final invLen = 1.0 / len;
        _normals[pIdx] = nx * invLen;
        _normals[pIdx + 1] = ny * invLen;
        _normals[pIdx + 2] = nz * invLen;
      }
    }

    // Upload updated buffer data to GPU
    _geometry.updatePositions(_positions);
    _geometry.updateNormals(_normals);
    _geometry.updateColors(_colors);
  }
}

