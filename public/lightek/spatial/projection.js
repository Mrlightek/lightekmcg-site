// Window lies on z=0, Y is up, viewer is at z>0; scene geometry lies behind it.
export function windowFrustum(eye, width, height, near = 0.02, far = 100) {
  if (![eye.x, eye.y, eye.z, width, height, near, far].every(Number.isFinite) ||
      eye.z <= near || width <= 0 || height <= 0 || near <= 0 || far <= near) {
    throw new RangeError('A window needs finite dimensions and an eye in front of its near plane.');
  }
  return {left: (-width / 2 - eye.x) * near / eye.z,
    right: (width / 2 - eye.x) * near / eye.z,
    top: (height / 2 - eye.y) * near / eye.z,
    bottom: (-height / 2 - eye.y) * near / eye.z, near, far};
}

export function applyWindowProjection(camera, eye, width, height) {
  const f = windowFrustum(eye, width, height, camera.near, camera.far);
  camera.position.set(eye.x, eye.y, eye.z);
  camera.up.set(0, 1, 0);
  camera.quaternion.identity(); // Do not lookAt(window center): that would rotate the physical window.
  camera.projectionMatrix.makePerspective(f.left, f.right, f.top, f.bottom, f.near, f.far);
  camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
  camera.updateMatrixWorld(true);
  return f;
}

export function faceMeasurement(landmarks, aspect = 4 / 3) {
  const left = landmarks?.[33], right = landmarks?.[263];
  if (!left || !right) return null;
  const x = (left.x + right.x) / 2, y = (left.y + right.y) / 2;
  const span = Math.hypot((right.x - left.x) * aspect, right.y - left.y);
  // Eye span is less sensitive to expression than a face bounding box; yaw still affects it.
  return [x, y, span].every(Number.isFinite) && span > 0.015 ? {x, y, span} : null;
}

export class HeadPose {
  constructor({distance = 0.6, fov = 55, mirror = true} = {}) {
    this.distance = distance; this.fov = fov; this.mirror = mirror;
    this.reference = null; this.eye = {x: 0, y: 0, z: distance};
  }
  calibrate(measurement) {
    if (!measurement) throw new Error('Face not visible. Look toward the webcam, then calibrate.');
    this.reference = {...measurement}; this.eye = {x: 0, y: 0, z: this.distance};
  }
  estimate(measurement, aspect) {
    if (!measurement || !this.reference) return null;
    const clamp = (v, low, high) => Math.max(low, Math.min(high, v));
    // Apparent eye span gives relative distance, NOT metric MediaPipe landmark-z depth.
    const z = clamp(this.distance * this.reference.span / measurement.span, 0.25, 1.5);
    const halfWidth = z * Math.tan(this.fov * Math.PI / 360);
    return {x: clamp((measurement.x - this.reference.x) * 2 * halfWidth * (this.mirror ? -1 : 1), -0.35, 0.35),
      y: clamp((this.reference.y - measurement.y) * 2 * halfWidth / aspect, -0.25, 0.25), z};
  }
  smooth(target, seconds) {
    const alpha = 1 - Math.exp(-Math.min(Math.max(seconds, 0), 0.1) / 0.09);
    for (const axis of ['x', 'y', 'z']) this.eye[axis] += (target[axis] - this.eye[axis]) * alpha;
    return this.eye;
  }
}
