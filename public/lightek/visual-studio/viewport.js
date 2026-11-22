import * as THREE from "three";
import { GLTFLoader } from "../vendor/three/addons/loaders/GLTFLoader.js";
import { clone } from "../vendor/three/addons/utils/SkeletonUtils.js";
import { aspect, cameraFov, degrees, depth, mouthAt, transformAt } from "./scene-state.js";

const euler = value => new THREE.Euler(...value.map(degrees), "ZYX");
const fileType = asset => asset?.filename.split(".").at(-1).toLowerCase();

function gltfLoader() {
  const manager = new THREE.LoadingManager();
  manager.setURLModifier(url => {
    if (!url.startsWith("data:") && !url.startsWith("blob:")) throw new Error("Use a self-contained glTF.");
    return url;
  });
  return new GLTFLoader(manager);
}

export class Viewport {
  constructor(container, store, controls) {
    Object.assign(this, { container, store, controls, entries: [], models: new Map(), textures: new Map() });
    try {
      this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: false });
    } catch {
      controls.notice("WebGL is unavailable. You can still edit layers and render through Blender.");
      return;
    }
    this.renderer.setPixelRatio(Math.min(2, devicePixelRatio));
    this.renderer.setClearColor(0x3c3c3c, 1);
    this.canvas = this.renderer.domElement;
    this.canvas.setAttribute("aria-label", "Interactive scene viewport");
    container.append(this.canvas);
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(40, 1, 0.1, 1000);
    this.scene.add(new THREE.HemisphereLight(0xffffff, 0x555563, 1.5));
    const key = new THREE.DirectionalLight(0xffffff, 2);
    key.position.set(0, -4, 4);
    this.scene.add(key);
    this.resize = new ResizeObserver(() => this.draw());
    this.resize.observe(container);
    this.canvas.addEventListener("pointerdown", event => this.down(event));
    this.canvas.addEventListener("pointermove", event => this.move(event));
    this.canvas.addEventListener("lostpointercapture", () => {
      if (this.drag?.moved) this.controls.finish();
      this.drag = null;
    });
    this.canvas.addEventListener("wheel", event => {
      if (!event.deltaY) return;
      event.preventDefault();
      this.controls.zoom(Math.sign(event.deltaY));
    }, { passive: false });
  }

  sync(assets) {
    if (!this.scene) return;
    const layers = this.store.spec.layers;
    layers.forEach((layer, index) => {
      const asset = assets.get(layer.asset_id);
      const shapes = Object.entries(layer.mouth?.variants ?? {}).map(([shape, id]) => [shape, assets.get(id)?.file_url]);
      const signature = JSON.stringify([asset?.id, asset?.file_url, asset?.preview_url, layer.dimension_mode, layer.relief, shapes]);
      if (this.entries[index]?.signature !== signature) {
        this.remove(this.entries[index]);
        this.entries[index] = this.load(asset, index, layer.dimension_mode, layer.relief, shapes, signature);
      }
    });
    while (this.entries.length > layers.length) this.remove(this.entries.pop());
    this.draw();
  }

  remove(entry) {
    if (!entry) return;
    entry.live = false;
    this.scene.remove(entry.root);
    entry.owned.forEach(resource => resource.dispose());
  }

  load(asset, index, mode, relief, shapes, signature) {
    const root = new THREE.Group();
    root.userData.layer = index;
    const billboard = new THREE.Group();
    const art = new THREE.Group();
    root.add(billboard);
    billboard.add(art);
    this.scene.add(root);
    const entry = { root, billboard, art, signature, live: true, mouth: {}, owned: [], clips: [] };
    if (mode === "3d") this.model(entry, asset);
    else this.card(entry, asset?.file_url, relief).then(mesh => { entry.card = mesh; }).catch(() => this.placeholder(entry, "Artwork preview unavailable"));
    for (const [shape, url] of shapes) {
      this.card(entry, url).then(mesh => { if (mesh) entry.mouth[shape] = mesh; }).catch(() => {});
    }
    return entry;
  }

  async card(entry, url, relief = 0) {
    if (!url) throw new Error("Missing artwork");
    if (!this.textures.has(url)) {
      this.textures.set(url, new THREE.TextureLoader().loadAsync(url).then(texture => {
        texture.colorSpace = THREE.SRGBColorSpace;
        return texture;
      }).catch(error => {
        this.textures.delete(url);
        throw error;
      }));
    }
    const map = await this.textures.get(url);
    if (!entry.live) return;
    const { width, height } = map.image;
    const geometry = new THREE.PlaneGeometry(2 * width / Math.max(width, height), 2 * height / Math.max(width, height));
    const appearance = { map, transparent: true, side: THREE.DoubleSide, alphaTest: 0.01 };
    const material = relief ?
      new THREE.MeshStandardMaterial({ ...appearance, bumpMap: map, bumpScale: relief * 0.1 }) :
      new THREE.MeshBasicMaterial(appearance);
    entry.owned.push(geometry, material);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.visible = false;
    entry.art.add(mesh);
    requestAnimationFrame(() => this.draw());
    return mesh;
  }

  async model(entry, asset) {
    const original = ["glb", "gltf"].includes(fileType(asset));
    const url = original ? asset.file_url : asset?.preview_url;
    if (!url) return this.placeholder(entry, "Model preview unavailable");
    try {
      if (!this.models.has(url)) {
        this.models.set(url, fetch(url).then(response => {
          if (!response.ok) throw new Error("Could not load model");
          return response.arrayBuffer();
        }).then(data => gltfLoader().parseAsync(data, "")));
      }
      const model = await this.models.get(url);
      if (!entry.live) return;
      const object = clone(model.scene);
      object.rotation.x += Math.PI / 2;
      const unusable = [];
      object.traverse(node => {
        if (node.isLight || node.isCamera ||
            (asset.starter && /^Studio floor(?:\.|$)/.test(node.userData.lightek_object_name ?? node.name))) unusable.push(node);
        if (node.material) {
          const materials = Array.isArray(node.material) ? node.material : [node.material];
          materials.forEach(material => { material.envMapIntensity = 0; });
        }
      });
      unusable.forEach(node => node.removeFromParent());
      entry.art.add(object);
      entry.clips = model.animations;
      entry.mixer = new THREE.AnimationMixer(object);
      entry.nativePreview = !original;
      if (entry.root.userData.layer === this.store.selected) this.controls.loaded();
      this.draw();
    } catch {
      this.models.delete(url);
      this.placeholder(entry, "Model preview could not load");
    }
  }

  placeholder(entry, message) {
    if (!entry.live) return;
    entry.notice = message;
    const geometry = new THREE.BoxGeometry(1.2, 1.2, 1.2);
    const material = new THREE.MeshBasicMaterial({ color: 0x9c8cff, wireframe: true });
    entry.owned.push(geometry, material);
    entry.art.add(new THREE.Mesh(geometry, material));
    this.draw();
  }

  draw() {
    if (!this.renderer || !this.container.clientWidth || !this.container.clientHeight) return;
    const { spec, time, frame, selected } = this.store;
    const ratio = aspect(spec);
    const width = Math.min(this.container.clientWidth, this.container.clientHeight * ratio);
    const height = width / ratio;
    if (this.width !== width || this.height !== height) {
      this.renderer.setSize(width, height);
      Object.assign(this, { width, height });
    }
    const camera = transformAt(spec.camera, time);
    this.camera.aspect = ratio;
    this.camera.fov = cameraFov(camera.lens, ratio);
    this.camera.position.fromArray(camera.position);
    this.camera.rotation.copy(euler(camera.rotation));
    this.camera.updateProjectionMatrix();
    this.camera.updateMatrixWorld();
    this.entries.forEach((entry, i) => {
      const layer = spec.layers[i];
      if (!layer) return;
      const position = transformAt(layer, time);
      entry.root.position.fromArray(position.position);
      entry.root.position.y += depth(layer);
      entry.billboard.quaternion.copy(layer.dimension_mode === "3d" ? new THREE.Quaternion() : this.camera.quaternion);
      entry.art.rotation.copy(euler(position.rotation));
      entry.art.scale.fromArray(position.scale);
      if (entry.card) entry.card.visible = true;
      if (layer.mouth) {
        const active = mouthAt(layer.mouth, frame, spec.fps);
        for (const [shape, mesh] of Object.entries(entry.mouth)) {
          mesh.position.fromArray(layer.mouth.position);
          mesh.position.z += 0.005;
          mesh.scale.fromArray(layer.mouth.scale);
          mesh.visible = shape === active;
        }
      }
      if (entry.mixer && entry.clips.length) {
        const clip = layer.action ? entry.clips.find(item => item.name === layer.action) : entry.clips[0];
        if (entry.activeClip !== clip) {
          entry.mixer.stopAllAction();
          if (clip) entry.mixer.clipAction(clip).setLoop(THREE.LoopOnce, 1).play().clampWhenFinished = true;
          entry.activeClip = clip;
        }
        if (clip) {
          const action = entry.mixer.clipAction(clip);
          action.paused = false;
          action.enabled = true;
          entry.mixer.setTime(layer.pose_frame === undefined ? time / 1000 : Math.max(0, layer.pose_frame - 1) / spec.fps);
        }
      }
    });
    this.renderer.render(this.scene, this.camera);
    const target = this.entries[selected];
    this.controls.notice(target?.notice || (target?.nativePreview ? "Native model proxy · Blender applies native rig actions on export" :
      !spec.layers.length ? "Add artwork or a model from Assets to start." : ""));
  }

  point(event) {
    const bounds = this.canvas.getBoundingClientRect();
    return new THREE.Vector2(2 * (event.clientX - bounds.left) / bounds.width - 1, 1 - 2 * (event.clientY - bounds.top) / bounds.height);
  }

  down(event) {
    if (event.button !== 0) return;
    const ray = new THREE.Raycaster();
    ray.setFromCamera(this.point(event), this.camera);
    const hit = ray.intersectObjects(this.entries.map(entry => entry.root)).find(({ object }) => {
      for (let item = object; item; item = item.parent) if (!item.visible) return false;
      return true;
    });
    let root = hit?.object;
    while (root && root.userData.layer === undefined) root = root.parent;
    const selection = !event.altKey && root ? root.userData.layer : "camera";
    this.controls.select(selection);
    const position = new THREE.Vector3().fromArray(transformAt(this.store.channel, this.store.time).position);
    const normal = this.camera.getWorldDirection(new THREE.Vector3());
    const anchor = selection === "camera" ? this.camera.position.clone().addScaledVector(normal, 8) : root.position;
    const plane = new THREE.Plane().setFromNormalAndCoplanarPoint(normal, anchor);
    const start = ray.ray.intersectPlane(plane, new THREE.Vector3());
    if (!start) return;
    this.drag = { plane, start, position, selection, camera: this.camera.clone(), x: event.clientX, y: event.clientY };
    this.canvas.setPointerCapture(event.pointerId);
  }

  move(event) {
    if (!this.drag) return;
    const { plane, start, position, selection, camera, x, y } = this.drag;
    if (!this.drag.moved && Math.hypot(event.clientX - x, event.clientY - y) < 3) return;
    const ray = new THREE.Raycaster();
    ray.setFromCamera(this.point(event), camera);
    const end = ray.ray.intersectPlane(plane, new THREE.Vector3());
    if (!end) return;
    this.drag.moved = true;
    this.controls.move(position.clone().addScaledVector(end.sub(start), selection === "camera" ? -1 : 1).toArray());
  }
}
