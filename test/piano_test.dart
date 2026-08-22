import 'dart:typed_data';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MeshGeometry.fromArrays with 256x256 grid', () {
    const cols = 256;
    const rows = 256;
    const vertexCount = cols * rows;

    final positions = Float32List(vertexCount * 3);
    final normals = Float32List(vertexCount * 3);
    final colors = Float32List(vertexCount * 4);
    final texCoords = Float32List(vertexCount * 2);

    final quadCount = (cols - 1) * (rows - 1);
    final triangleCount = quadCount * 4;
    final indices32 = Uint32List(triangleCount * 3);
    final indices16 = Uint16List(triangleCount * 3);

    // Test indices parameter type
    final geo32 = MeshGeometry.fromArrays(
      positions: positions,
      normals: normals,
      colors: colors,
      texCoords: texCoords,
      indices: indices32,
      storage: GeometryStorage.updatable,
    );
    expect(geo32, isNotNull);

    final geo16 = MeshGeometry.fromArrays(
      positions: positions,
      normals: normals,
      colors: colors,
      texCoords: texCoords,
      indices: indices16,
      storage: GeometryStorage.updatable,
    );
    expect(geo16, isNotNull);
  });
}
