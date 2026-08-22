import 'package:flutter_test/flutter_test.dart';
import 'package:piano_3d/scene/camera_orbit_controller.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('CameraOrbitController computes valid perspective camera and rays', () {
    final controller = CameraOrbitController(
      target: vm.Vector3(0.0, 0.20, -0.15),
      yaw: 0.0,
      pitch: 0.45,
      distance: 4.0,
    );

    final camera = controller.getCamera();
    expect(camera.target, equals(vm.Vector3(0.0, 0.20, -0.15)));
    expect(camera.position.y, greaterThan(0.0));

    final ray = controller.screenPointToRay(400, 300, 800, 600);
    expect(ray.direction.length, closeTo(1.0, 0.001));

    final hit = ray.intersectPlaneY(0.05);
    expect(hit, isNotNull);
  });
}
