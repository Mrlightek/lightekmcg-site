/* Interactive previews of the saved Blender command contract, in object-local space. */
import * as THREE from "./vendor/three/three.module.js";

const baselines = new WeakMap();
const axes = { X: 0, Y: 1, Z: 2 };

export function nativeObjectRoot(node, definition, sourceWorld) {
  const root = new THREE.Group();
  const setTransform = d => {
    root.position.fromArray(d.location || [0,0,0]);
    root.rotation.set(...(d.rotation || [0,0,0]).map(THREE.MathUtils.degToRad));
    root.scale.fromArray(d.scale || [1,1,1]);
  };
  // Establish the original object basis before applying the user's saved TRS.
  // Reparenting directly under the edited TRS would cancel those saved edits.
  node.removeFromParent();
  sourceWorld.decompose(node.position,node.quaternion,node.scale);
  setTransform(definition.viewport_source_transform || definition.native_original || definition);
  root.updateMatrixWorld(true);
  root.attach(node);
  setTransform(definition);
  root.visible = !definition.hide_viewport && !definition.native_deleted;
  return root;
}

export function previewMeshCommands(root, commands) {
  let baseline = baselines.get(root);
  const restore = () => {
    for (const { mesh, positions } of baseline || []) {
      mesh.geometry.attributes.position.array.set(positions);
      updateGeometry(mesh.geometry);
    }
  };
  if (!commands.length) {
    restore();
    return { ok: true };
  }
  if (commands.some(c => c.kind !== "mesh_skew")) {
    restore();
    return { ok: false, reason: "Update Blender viewport to preview the earlier mesh edits first." };
  }
  if (commands.some(c => !(c.axis in axes) || !(c.source_axis in axes) || c.axis === c.source_axis || !Number.isFinite(c.factor) || Math.abs(c.factor) > 2 || c.indices?.length)) {
    restore();
    return { ok: false, reason: "This selection needs a Blender viewport update." };
  }
  const meshes = [];
  root.traverse(mesh => { if (mesh.isMesh) meshes.push(mesh); });
  if (root.userData.nativePlaceholder || !meshes.length || meshes.some(m => m.isSkinnedMesh || m.isInstancedMesh || Object.keys(m.geometry.morphAttributes || {}).length) || meshes.reduce((n,m) => n + (m.geometry.attributes.position?.count || 0), 0) > 500000) {
    restore();
    return { ok: false, reason: "This mesh needs a Blender viewport update for an accurate preview." };
  }
  if (!baseline) {
    baseline = meshes.map(mesh => {
      mesh.geometry = mesh.geometry.clone();
      return { mesh, positions: mesh.geometry.attributes.position.array.slice() };
    });
    baselines.set(root, baseline);
  }
  root.updateWorldMatrix(true, true);
  if (Math.abs(root.matrixWorld.determinant()) < 1e-12) {
    restore();
    return { ok: false, reason: "Use a nonzero object scale to preview skew." };
  }
  const worldToObject = root.matrixWorld.clone().invert();
  const point = new THREE.Vector3();
  for (const { mesh, positions } of baseline) {
    const toObject = worldToObject.clone().multiply(mesh.matrixWorld);
    const toMesh = toObject.clone().invert();
    const attribute = mesh.geometry.attributes.position;
    for (let i = 0; i < attribute.count; i++) {
      point.fromArray(positions, i * 3).applyMatrix4(toObject);
      const values = point.toArray();
      for (const command of commands) values[axes[command.axis]] += command.factor * values[axes[command.source_axis]];
      point.fromArray(values).applyMatrix4(toMesh);
      attribute.setXYZ(i, point.x, point.y, point.z);
    }
    updateGeometry(mesh.geometry);
  }
  return { ok: true };
}

function updateGeometry(geometry) {
  geometry.attributes.position.needsUpdate = true;
  geometry.computeVertexNormals();
  geometry.computeBoundingBox();
  geometry.computeBoundingSphere();
}
