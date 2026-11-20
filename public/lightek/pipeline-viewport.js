import * as THREE from "./vendor/three/three.module.js";
import { GLTFLoader } from "./vendor/three/addons/loaders/GLTFLoader.js";
import { OrbitControls } from "./vendor/three/addons/controls/OrbitControls.js";
import { TransformControls } from "./vendor/three/addons/controls/TransformControls.js";

const radians = THREE.MathUtils.degToRad;
const degrees = THREE.MathUtils.radToDeg;

export class PipelineViewport {
  constructor(container, onMove = () => {}) {
    this.container = container;
    this.entries = new Map();
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x171a20);
    this.camera = new THREE.PerspectiveCamera(45, 1, 0.01, 10000);
    this.camera.up.set(0, 0, 1);
    this.camera.position.set(4, -7, 3);
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio || 1, 2));
    this.renderer.toneMapping = THREE.AgXToneMapping;
    container.append(this.renderer.domElement);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 0, 0.8);
    this.controls.update();
    this.transform = new TransformControls(this.camera, this.renderer.domElement);
    this.transform.addEventListener("dragging-changed", ({value}) => { this.controls.enabled = !value; });
    this.transform.addEventListener("objectChange", () => {
      const object = this.transform.object;
      if (object) onMove(object.userData.objectId, object.position.toArray());
    });
    this.scene.add(this.transform.getHelper());
    const grid = new THREE.GridHelper(36, 36, 0x676777, 0x343846);
    grid.rotation.x = Math.PI / 2;
    this.scene.add(grid, new THREE.HemisphereLight(0xe9f2ff, 0x8b7150, 2));
    const light = new THREE.DirectionalLight(0xffecd6, 2.2);
    light.position.set(-3, -3, 6);
    this.scene.add(light);
    this.setTool("orbit");
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(container);
    this.resize();
    let previous = performance.now();
    this.renderer.setAnimationLoop((time) => {
      const delta = Math.min(Math.max((time - previous) / 1000, 0), 0.1);
      previous = time;
      this.entries.forEach((entry) => entry.mixer?.update(delta));
      this.renderer.render(this.scene, this.camera);
    });
  }

  setAspect(aspect) {
    this.outputAspect = aspect;
    this.resize();
  }

  resize() {
    let width = Math.max(this.container.clientWidth, 1);
    let height = Math.max(this.container.clientHeight, 1);
    if (this.outputAspect) {
      if (width / height > this.outputAspect) width = Math.round(height * this.outputAspect);
      else height = Math.round(width / this.outputAspect);
    }
    this.renderer.setSize(width, height, true);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  setTool(tool) {
    this.tool = tool;
    this.select(this.selection);
  }

  select(id) {
    this.selection = id;
    const entry = this.entries.get(id);
    this.transform.detach();
    if (entry && this.tool === "translate") this.transform.attach(entry.root);
  }

  async load(row, asset) {
    const root = new THREE.Group();
    root.userData.objectId = row.id;
    const axis = new THREE.Group();
    // glTF Y-up coordinates are converted to Blender Z-up for the composer.
    axis.rotation.x = Math.PI / 2;
    root.add(axis);
    this.scene.add(root);
    const entry = {root, clipName: undefined, loop: undefined};
    this.entries.set(row.id, entry);
    this.update(row);
    try {
      const gltf = await new GLTFLoader().loadAsync(asset.previewUrl);
      if (this.entries.get(row.id) !== entry) {
        this.disposeModel(gltf.scene);
        return;
      }
      axis.add(gltf.scene);
      entry.mixer = new THREE.AnimationMixer(gltf.scene);
      const names = asset.clips || [];
      entry.clips = gltf.animations.map((clip, index) => ({
        name: names[index] || clip.name, clip
      }));
      this.update(row);
      this.select(this.selection);
    } catch (error) {
      this.remove(row.id);
      throw error;
    }
  }

  update(row) {
    const entry = this.entries.get(row.id);
    if (!entry) return;
    entry.root.position.fromArray(row.position);
    entry.root.rotation.set(...row.rotationEulerDeg.map(radians), "ZYX");
    entry.root.scale.fromArray(row.scale);
    if (!entry.mixer || (entry.clipName === row.animationClip && entry.loop === row.loopAnimation)) return;
    entry.mixer.stopAllAction();
    entry.clipName = row.animationClip;
    entry.loop = row.loopAnimation;
    const clip = entry.clips.find((item) => item.name === row.animationClip)?.clip;
    if (clip) {
      const action = entry.mixer.clipAction(clip);
      action.setLoop(row.loopAnimation ? THREE.LoopRepeat : THREE.LoopOnce, row.loopAnimation ? Infinity : 1);
      action.clampWhenFinished = true;
      action.reset().play();
    }
  }

  frame() {
    const box = new THREE.Box3();
    this.entries.forEach(({root}) => box.expandByObject(root));
    if (box.isEmpty()) return;
    const ball = box.getBoundingSphere(new THREE.Sphere());
    const halfVertical = radians(this.camera.fov / 2);
    const halfHorizontal = Math.atan(Math.tan(halfVertical) * this.camera.aspect);
    const distance = Math.max(ball.radius, 0.15) * 1.24 / Math.sin(Math.min(halfVertical, halfHorizontal));
    const direction = this.camera.position.clone().sub(this.controls.target).normalize();
    this.controls.target.copy(ball.center);
    this.camera.position.copy(ball.center).addScaledVector(direction, distance);
    this.controls.update();
  }

  cameraSpec() {
    const values = (vector) => vector.toArray().map((value) => Number(value.toFixed(6)));
    return {position: values(this.camera.position), target: values(this.controls.target),
      fov: degrees(2 * Math.atan(Math.tan(radians(this.camera.fov / 2)) * this.camera.aspect))};
  }

  disposeModel(root) {
    const dispose = new Set();
    root.traverse((node) => {
      if (node.geometry) dispose.add(node.geometry);
      for (const material of [node.material].flat().filter(Boolean)) {
        Object.values(material).forEach((value) => { if (value?.isTexture) dispose.add(value); });
        dispose.add(material);
      }
      if (node.skeleton) dispose.add(node.skeleton);
    });
    dispose.forEach((item) => item.dispose());
  }

  remove(id) {
    const entry = this.entries.get(id);
    if (!entry) return;
    if (this.selection === id) this.select(null);
    entry.mixer?.stopAllAction();
    entry.root.removeFromParent();
    this.disposeModel(entry.root);
    this.entries.delete(id);
  }

  dispose() {
    [...this.entries.keys()].forEach((id) => this.remove(id));
    this.resizeObserver.disconnect();
    this.renderer.setAnimationLoop(null);
    this.controls.dispose();
    this.transform.dispose();
    this.disposeModel(this.scene);
    this.renderer.dispose();
    this.renderer.domElement.remove();
  }
}
