import 'dart:math' as math;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Controller for smooth camera orbiting that always looks at the top center of the piano.
class CameraOrbitController {
  // Target focal point: top center of the piano
  final vm.Vector3 target;

  double yaw; // radians
  double pitch; // radians
  double distance;

  // Smoothing targets
  double _targetYaw;
  double _targetPitch;
  double _targetDistance;

  CameraOrbitController({
    vm.Vector3? target,
    this.yaw = 0.0,
    this.pitch = 0.45,
    this.distance = 4.0,
  })  : target = target ?? vm.Vector3(0.0, 0.25, -0.2),
        _targetYaw = yaw,
        _targetPitch = pitch,
        _targetDistance = distance;

  /// Adds delta yaw and pitch from pointer drag.
  void rotate(double deltaX, double deltaY) {
    _targetYaw -= deltaX * 0.006;
    _targetPitch += deltaY * 0.006;

    // Clamp pitch so camera stays above the floor / sea plane
    _targetPitch = _targetPitch.clamp(0.05, 1.35);
  }

  /// Adds zoom / dolly delta.
  void zoom(double deltaZoom) {
    _targetDistance = (_targetDistance + deltaZoom).clamp(2.0, 12.0);
  }

  /// Resets to default vantage view.
  void reset() {
    _targetYaw = 0.0;
    _targetPitch = 0.45;
    _targetDistance = 4.0;
  }

  /// Updates smooth camera easing.
  void update(double dt) {
    final t = math.min(1.0, dt * 12.0);
    yaw += (_targetYaw - yaw) * t;
    pitch += (_targetPitch - pitch) * t;
    distance += (_targetDistance - distance) * t;
  }

  /// Computes the camera eye position.
  vm.Vector3 getEyePosition() {
    final x = target.x + distance * math.cos(pitch) * math.sin(yaw);
    final y = target.y + distance * math.sin(pitch);
    final z = target.z + distance * math.cos(pitch) * math.cos(yaw);
    return vm.Vector3(x, y, z);
  }

  /// Creates the configured PerspectiveCamera looking directly at [target].
  PerspectiveCamera getCamera() {
    final eye = getEyePosition();
    return PerspectiveCamera(
      position: eye,
      target: target,
      up: vm.Vector3(0, 1, 0),
      fovRadiansY: 52 * vm.degrees2Radians,
      fovNear: 0.05,
      fovFar: 1000.0,
    );
  }

  /// Projects a normalized screen point (0..1) to a 3D ray in world space.
  Ray screenPointToRay(double screenX, double screenY, double viewportWidth, double viewportHeight) {
    final eye = getEyePosition();

    // Normalized Device Coordinates (-1 to 1)
    final ndcX = (screenX / viewportWidth) * 2.0 - 1.0;
    final ndcY = 1.0 - (screenY / viewportHeight) * 2.0;

    final fovY = 52 * vm.degrees2Radians;
    final aspect = viewportWidth / viewportHeight;
    final tanFovHalf = math.tan(fovY / 2.0);

    // Forward, right, up basis vectors
    final forward = (target - eye).normalized();
    final right = forward.cross(vm.Vector3(0, 1, 0)).normalized();
    final up = right.cross(forward).normalized();

    final rayDir = (forward + right * (ndcX * aspect * tanFovHalf) + up * (ndcY * tanFovHalf)).normalized();

    return Ray(origin: eye, direction: rayDir);
  }
}

/// Simple 3D ray with origin and direction.
class Ray {
  final vm.Vector3 origin;
  final vm.Vector3 direction;

  Ray({required this.origin, required this.direction});

  /// Intersects ray with horizontal XZ plane at [planeY]. Returns world intersection point or null.
  vm.Vector3? intersectPlaneY(double planeY) {
    if (direction.y.abs() < 1e-6) return null;
    final t = (planeY - origin.y) / direction.y;
    if (t < 0) return null;
    return origin + direction * t;
  }
}
