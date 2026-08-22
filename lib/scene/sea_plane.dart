import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// High-detail 128x128 triangulated mesh plane reacting to FFT audio data.
class SeaPlane {
  static const int cols = 128;
  static const int rows = 128;
  static const int vertexCount = cols * rows;

  final double width;
  final double depth;
  final vm.Vector3 origin;

  late final Float32List _positions;
  late final Float32List _normals;
  late final Float32List _colors;
  late final Float32List _texCoords;
  late final Uint16List _indices;

  late final MeshGeometry _geometry;
  late final PhysicallyBasedMaterial _material;
  late final Node node;

  // Persistent wave state
  final Float32List _fftPeakHistory = Float32List(rows);

  SeaPlane({this.width = 32.0, this.depth = 28.0, vm.Vector3? origin})
    : origin = origin ?? vm.Vector3(-16.0, -0.28, 1.20) {
    _initBuffers();
    _buildMesh();
  }

  void _initBuffers() {
    _positions = Float32List(vertexCount * 3);
    _normals = Float32List(vertexCount * 3);
    _colors = Float32List(vertexCount * 4);
    _texCoords = Float32List(vertexCount * 2);

    final triangleCount = (cols - 1) * (rows - 1) * 2;
    _indices = Uint16List(triangleCount * 3);

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
        _colors[cIdx] = 0.03;
        _colors[cIdx + 1] = 0.12;
        _colors[cIdx + 2] = 0.28;
        _colors[cIdx + 3] = 1.0;

        _texCoords[tIdx] = u;
        _texCoords[tIdx + 1] = v;
        tIdx += 2;

        vIdx++;
      }
    }

    // Two triangles per quad (wound so face points +Y up)
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

    // Procedural ocean water material with high specularity and reflections
    _material = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.04, 0.25, 0.45, 0.95)
      ..roughnessFactor = 0.10
      ..metallicFactor = 0.15
      ..clearcoat = 1.0
      ..clearcoatRoughness = 0.06
      ..vertexColorWeight = 1.0;

    node = Node(name: 'SeaPlane', mesh: Mesh(_geometry, _material))
      ..raycastable = false;
  }

  /// Updates mesh vertices, normals, and vertex colors based on elapsed time and FFT data.
  void update(double time, Float32List fftData) {
    final dx = width / (cols - 1);
    final dz = depth / (rows - 1);
    final fftLen = fftData.length;

    // Shift FFT history across rows for a travelling wave wake effect
    double avgFft = 0.0;
    if (fftLen > 0) {
      for (var i = 0; i < fftLen; i++) {
        avgFft += fftData[i];
      }
      avgFft /= fftLen;
    }

    for (var r = rows - 1; r > 0; r--) {
      _fftPeakHistory[r] = _fftPeakHistory[r - 1] * 0.96;
    }
    _fftPeakHistory[0] = avgFft;

    // Update positions and colors
    var vIdx = 0;
    for (var r = 0; r < rows; r++) {
      final zNorm = r / (rows - 1);
      final rowHistory = _fftPeakHistory[r];

      for (var c = 0; c < cols; c++) {
        final colNorm = c / (cols - 1);
        final xNorm = (colNorm - 0.5) * 2.0; // -1 to 1

        // Map column to FFT bin (range 15-180 mapped to 0..165)
        double fftVal = 0.0;
        if (fftLen > 0) {
          final bin = ((colNorm * (fftLen - 1)).clamp(0, fftLen - 1)).toInt();
          fftVal = fftData[bin];
        }

        // Procedural ocean waves
        final x = origin.x + (c * dx);
        final z = origin.z + (r * dz);

        final wave1 = math.sin(x * 0.45 + time * 1.8 + z * 0.2) * 0.22;
        final wave2 = math.cos(z * 0.65 - time * 1.4 + x * 0.3) * 0.15;
        final wave3 = math.sin((x * 0.8 + z * 0.8) + time * 2.5) * 0.08;
        final microRipple = math.sin(x * 2.5 + z * 2.5 + time * 4.0) * 0.03;

        // FFT pulse and directional ripples radiating outwards from the piano
        final distFromPiano = math.sqrt(
          xNorm * xNorm + (zNorm * 1.5) * (zNorm * 1.5),
        );
        final fftRipple =
            math.sin(distFromPiano * 14.0 - time * 6.0) * (fftVal * 0.8);
        final fftRowWave = rowHistory * math.cos(x * 0.5 + time * 2.0) * 0.6;
        final fftColumnLift = fftVal * 1.4 * (1.0 - zNorm * 0.5);

        final height =
            origin.y +
            wave1 +
            wave2 +
            wave3 +
            microRipple +
            fftColumnLift +
            fftRipple +
            fftRowWave;

        final pIdx = vIdx * 3;
        _positions[pIdx + 1] = height;

        // Dynamic vertex color shading: deep ocean blue in troughs, luminous turquoise on crests, white foam at peaks
        final normalizedH = (height - origin.y + 0.3) / 1.5;
        final peakEnergy = (normalizedH.clamp(0.0, 1.0) * 0.7 + fftVal * 0.5)
            .clamp(0.0, 1.0);

        final cIdx = vIdx * 4;
        // Interpolate between deep sapphire (0.02, 0.08, 0.22) and bright cyan-foam (0.2, 0.9, 0.95)
        _colors[cIdx] = 0.02 + peakEnergy * 0.35;
        _colors[cIdx + 1] = 0.08 + peakEnergy * 0.65;
        _colors[cIdx + 2] = 0.22 + peakEnergy * 0.75;
        _colors[cIdx + 3] = 1.0;

        vIdx++;
      }
    }

    // Recalculate surface normals
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final pIdx = idx * 3;

        final cPrev = (c - 1).clamp(0, cols - 1);
        final cNext = (c + 1).clamp(0, cols - 1);
        final rPrev = (r - 1).clamp(0, rows - 1);
        final rNext = (r + 1).clamp(0, rows - 1);

        final leftIdx = (r * cols + cPrev) * 3;
        final rightIdx = (r * cols + cNext) * 3;
        final topIdx = (rPrev * cols + c) * 3;
        final bottomIdx = (rNext * cols + c) * 3;

        final hL = _positions[leftIdx + 1];
        final hR = _positions[rightIdx + 1];
        final hT = _positions[topIdx + 1];
        final hB = _positions[bottomIdx + 1];

        final nx = -(hR - hL) / (2.0 * dx);
        final nz = -(hB - hT) / (2.0 * dz);
        final ny = 1.0;

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
