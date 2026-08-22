import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Controller for smooth camera orbiting that always looks at the top center of the piano.
class CameraOrbitController {
  // Target focal point: top center of the piano
  final vm.Vector3 target;

  double yaw; // radians (0 = looking straight at piano from front)
  double pitch; // radians (elevation angle)
  double distance;

  // Smoothing targets
  double _targetYaw;
  double _targetPitch;
  double _targetDistance;

  CameraOrbitController({
    vm.Vector3? target,
    this.yaw = 0.0,
    this.pitch = 0.44,
    this.distance = 2.2,
  }) : target = target ?? vm.Vector3(0.0, 1.935, 0.20),
       _targetYaw = yaw,
       _targetPitch = pitch,
       _targetDistance = distance;

  /// Adds delta yaw and pitch from pointer drag.
  void rotate(double deltaX, double deltaY) {
    _targetYaw -= deltaX * 0.0055;
    _targetPitch += deltaY * 0.0055;

    // Clamp pitch so camera stays comfortably above the piano
    _targetPitch = _targetPitch.clamp(0.05, 1.38);
  }

  /// Adds zoom / dolly delta.
  void zoom(double deltaZoom) {
    _targetDistance = (_targetDistance + deltaZoom).clamp(1.2, 8.0);
  }

  /// Resets to default vantage view.
  void reset() {
    _targetYaw = 0.0;
    _targetPitch = 0.44;
    _targetDistance = 2.2;
  }

  /// Updates smooth camera easing.
  void update(double dt) {
    final t = math.min(1.0, dt * 14.0);
    yaw += (_targetYaw - yaw) * t;
    pitch += (_targetPitch - pitch) * t;
    distance += (_targetDistance - distance) * t;
  }

  /// Computes the camera eye position in world space.
  /// Sits at negative Z in front of target when yaw = 0, elevated at +Y.
  vm.Vector3 getEyePosition() {
    final horizontalDist = distance * math.cos(pitch);
    final x = target.x + horizontalDist * math.sin(yaw);
    final y = target.y + distance * math.sin(pitch);
    final z = target.z - horizontalDist * math.cos(yaw);
    return vm.Vector3(x, y, z);
  }

  /// Creates the configured PerspectiveCamera looking directly at [target].
  PerspectiveCamera getCamera() {
    final eye = getEyePosition();
    return PerspectiveCamera(
      position: eye,
      target: target,
      up: vm.Vector3(0, 1, 0),
      fovRadiansY: 50 * vm.degrees2Radians,
      fovNear: 0.05,
      fovFar: 1000.0,
    );
  }

  /// Exact 3D ray generation from screen coordinates using the camera's inverse View-Projection matrix.
  Ray screenPointToRay(
    double screenX,
    double screenY,
    double viewportWidth,
    double viewportHeight,
  ) {
    final eye = getEyePosition();
    const fovY = 50.0 * vm.degrees2Radians;
    final aspect = viewportWidth / viewportHeight;

    // View matrix: looks from eye to target with up (0, 1, 0)
    final viewMatrix = vm.makeViewMatrix(eye, target, vm.Vector3(0, 1, 0));
    // Perspective projection matrix
    final projMatrix = vm.makePerspectiveMatrix(fovY, aspect, 0.05, 1000.0);

    // Combined View-Projection matrix & its inverse
    final vp = projMatrix * viewMatrix;
    final invVP = vm.Matrix4.inverted(vp);

    // Normalized Device Coordinates (-1 to 1)
    final ndcX = (screenX / viewportWidth) * 2.0 - 1.0;
    final ndcY = 1.0 - (screenY / viewportHeight) * 2.0;

    // Unproject near plane point (ndcZ = -1.0) and far plane point (ndcZ = 1.0)
    final nearVec = vm.Vector4(ndcX, ndcY, -1.0, 1.0);
    invVP.transform(nearVec);
    final nearPoint = vm.Vector3(
      nearVec.x / nearVec.w,
      nearVec.y / nearVec.w,
      nearVec.z / nearVec.w,
    );

    final farVec = vm.Vector4(ndcX, ndcY, 1.0, 1.0);
    invVP.transform(farVec);
    final farPoint = vm.Vector3(
      farVec.x / farVec.w,
      farVec.y / farVec.w,
      farVec.z / farVec.w,
    );

    final rayDir = (farPoint - nearPoint).normalized();
    return Ray(origin: eye, direction: rayDir);
  }
}

/// 3D Ray representation with origin and normalized direction.
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
