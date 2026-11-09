import * as THREE from "../vendor/three/three.module.js";
import { GLTFLoader } from "../vendor/three/addons/loaders/GLTFLoader.js";
export class StageComposer {
  constructor(width = 1280, height = 720) {
    this.width = width;
    this.height = height;
    this.ready = false;
    this.elapsed = 0;
    this.last = 0;
    this.renderer = new THREE.WebGLRenderer({
      antialias: true,
      preserveDrawingBuffer: true,
    });
    this.renderer.setSize(width, height);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color("#101924");
    this.camera = new THREE.PerspectiveCamera(45, width / height, 0.01, 10000);
    this.camera.up.set(0, 0, 1);
    this.scene.add(new THREE.HemisphereLight(0xd5e8ff, 0x22232e, 2));
    const key = new THREE.DirectionalLight(0xffffff, 3);
    key.position.set(4, -6, 8);
    this.scene.add(key);
    this.subject = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.ShaderMaterial({
        side: THREE.DoubleSide,
        transparent: true,
        depthWrite: true,
        uniforms: {
          map: { value: null },
          keyColor: { value: new THREE.Color("#00ff00") },
          keyEnabled: { value: 1 },
          threshold: { value: 0.4 },
          softness: { value: 0.08 },
        },
        vertexShader:
          "varying vec2 vUv; void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);}",
        fragmentShader:
          "uniform sampler2D map;uniform vec3 keyColor;uniform float keyEnabled;uniform float threshold;uniform float softness;varying vec2 vUv;void main(){vec4 c=texture2D(map,vUv);float d=distance(c.rgb,keyColor);float a=keyEnabled<0.5?1.0:smoothstep(threshold,threshold+softness,d);if(a<0.02)discard;gl_FragColor=vec4(c.rgb,c.a*a);}",
      }),
    );
    this.subject.visible = false;
    this.scene.add(this.subject);
    this.cameras = [];
  }
  async load(url) {
    if (!/^\/api\/lightek\/pwa\/assets\/\d+\/proxy$/.test(url))
      throw Error("Choose a prepared Studio model.");
    const gltf = await new GLTFLoader().setWithCredentials(true).loadAsync(url);
    if (this.model) this.disposeModel();
    this.model = gltf.scene;
    this.model.rotation.x = Math.PI / 2;
    this.scene.add(this.model);
    this.scene.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(this.model),
      center = box.getCenter(new THREE.Vector3()),
      size = box.getSize(new THREE.Vector3()),
      radius = Math.max(size.length() / 2, 1);
    this.camera.position
      .copy(center)
      .add(new THREE.Vector3(radius, -radius * 1.7, radius * 0.8));
    this.camera.lookAt(center);
    this.camera.updateProjectionMatrix();
    this.cameras = gltf.cameras || [];
    this.mixer = new THREE.AnimationMixer(this.model);
    for (const clip of gltf.animations) this.mixer.clipAction(clip).play();
    this.ready = true;
    this.last = 0;
    this.render(0);
    return this.cameras.map((camera, index) => ({
      index,
      name: camera.name || "Blender camera " + (index + 1),
    }));
  }
  setCamera(value) {
    this.activeCamera = value === "" ? null : this.cameras[Number(value)];
    if (this.activeCamera) {
      this.activeCamera.aspect = this.width / this.height;
      this.activeCamera.updateProjectionMatrix();
    }
  }
  setSubject(
    video,
    {
      enabled = true,
      key = true,
      color = "#00ff00",
      threshold = 0.4,
      x = 0,
      depth = 0,
      z = 1.5,
      height = 3,
    } = {},
  ) {
    const canvasSource = video?.tagName === 'CANVAS';
    const ready = enabled && (canvasSource || video?.readyState >= 2);
    this.subject.visible = !!ready;
    if (!ready) return;
    if (this.video !== video) {
      this.texture?.dispose();
      this.texture = canvasSource ? new THREE.CanvasTexture(video) : new THREE.VideoTexture(video);
      this.texture.colorSpace = THREE.SRGBColorSpace;
      this.video = video;
      this.subject.material.uniforms.map.value = this.texture;
    }
    this.texture.needsUpdate = true;
    this.subject.material.uniforms.keyEnabled.value = key ? 1 : 0;
    this.subject.material.uniforms.keyColor.value.set(color);
    this.subject.material.uniforms.threshold.value = Number(threshold);
    this.subject.position.set(Number(x), Number(depth), Number(z));
    this.subject.scale.set(
      (Number(height) * (video.videoWidth || video.width)) / (video.videoHeight || video.height),
      Number(height),
      1,
    );
    (this.activeCamera || this.camera).getWorldQuaternion(
      this.subject.quaternion,
    );
  }
  render(now = performance.now()) {
    if (this.mixer && this.last)
      this.mixer.update(Math.min(0.1, Math.max(0, (now - this.last) / 1000)));
    this.last = now;
    this.renderer.render(this.scene, this.activeCamera || this.camera);
    return this.renderer.domElement;
  }
  disposeModel() {
    this.model.traverse((node) => {
      node.geometry?.dispose();
      for (const material of Array.isArray(node.material)
        ? node.material
        : node.material
          ? [node.material]
          : [])
        material.dispose();
    });
    this.scene.remove(this.model);
    this.model = null;
    this.mixer?.stopAllAction();
  }
  dispose() {
    this.ready = false;
    if (this.model) this.disposeModel();
    this.texture?.dispose();
    this.subject.geometry.dispose();
    this.subject.material.dispose();
    this.renderer.dispose();
  }
}
