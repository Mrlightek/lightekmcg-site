import * as THREE from '../vendor/three/three.module.js';
import {OrbitControls} from '../vendor/three/addons/controls/OrbitControls.js';
import {applyWindowProjection} from './projection.js';

const vertexShader = `
  uniform sampler2D mask; uniform float useMask; uniform float depth; uniform float mirror;
  varying vec2 videoUV;
  void main() {
    videoUV = uv;
    vec3 displaced = position;
    displaced.z += texture2D(mask, vec2(mix(uv.x, 1.0 - uv.x, mirror), uv.y)).r * useMask * depth;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(displaced, 1.0);
  }`;
const fragmentShader = `
  uniform sampler2D video; uniform sampler2D mask;
  uniform float useMask; uniform float opacity; uniform float mirror;
  varying vec2 videoUV;
  void main() {
    vec2 uv = vec2(mix(videoUV.x, 1.0 - videoUV.x, mirror), videoUV.y);
    vec4 color = sRGBTransferEOTF(texture2D(video, uv));
    float alpha = mix(1.0, smoothstep(0.25, 0.75, texture2D(mask, uv).r), useMask);
    gl_FragColor = vec4(color.rgb, alpha * opacity);
    #include <tonemapping_fragment>
    #include <colorspace_fragment>
  }`;

export class SpatialCompositor {
  constructor(host, {width = 0.5} = {}) {
    this.host = host; this.width = width; this.surfaces = [];
    this.scene = new THREE.Scene(); this.scene.background = new THREE.Color('#101825');
    const fill=new THREE.HemisphereLight(0xffffff,0x152235,1.6),key=new THREE.DirectionalLight(0xffffff,2);key.position.set(2,3,4);this.scene.add(fill,key);
    this.camera = new THREE.PerspectiveCamera(45, 1, 0.02, 100);
    this.camera.up.set(0,1,0);this.camera.position.set(0,0,.6);
    this.renderer = new THREE.WebGLRenderer({antialias:true,alpha:false});
    this.renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 1.5));
    this.renderer.outputColorSpace=THREE.SRGBColorSpace;
    this.renderer.domElement.setAttribute('aria-label','Spatial video and holographic window');
    this.renderer.domElement.style.cssText='width:100%;height:100%;display:block;touch-action:none';
    host.append(this.renderer.domElement);
    this.controls = new OrbitControls(this.camera,this.renderer.domElement);
    this.controls.target.set(0,0,-.4);this.controls.enableDamping=true;
    this.controls.enabled=false;this.controls.minDistance=.25;this.controls.maxDistance=4;
    this.mask = new THREE.DataTexture(new Uint8Array([255]),1,1,THREE.RedFormat);
    this.mask.needsUpdate=true;this.mask.flipY=true;this.mask.unpackAlignment=1;
    this.marker = new THREE.Mesh(new THREE.TorusKnotGeometry(.09,.025,80,12),new THREE.MeshNormalMaterial());
    this.marker.position.set(.13,.025,-.6);this.scene.add(this.marker);
    const back = new THREE.Mesh(new THREE.PlaneGeometry(2,2),new THREE.MeshBasicMaterial({color:0x223b59}));
    back.position.z=-1.4;this.scene.add(back);
    // Visible depth references behind and in front of the webcam plane.
    this.cube = new THREE.Mesh(new THREE.BoxGeometry(.08,.08,.08),new THREE.MeshNormalMaterial());
    this.cube.position.set(-.15,.04,-.1);this.scene.add(this.cube);
    this.resize = new ResizeObserver(()=>this.resizeToHost());this.resize.observe(host);this.resizeToHost();
  }
  resizeToHost() {
    const width=Math.max(1,this.host.clientWidth),height=Math.max(1,this.host.clientHeight);
    this.aspect=width/height;this.camera.aspect=this.aspect;this.renderer.setSize(width,height,false);
  }
  add(item) {
    const texture=new THREE.VideoTexture(item.video);texture.colorSpace=THREE.SRGBColorSpace;
    texture.minFilter=THREE.LinearFilter;texture.magFilter=THREE.LinearFilter;
    const material=new THREE.ShaderMaterial({vertexShader,fragmentShader,transparent:true,side:THREE.DoubleSide,depthWrite:false,
      uniforms:{video:{value:texture},mask:{value:this.mask},useMask:{value:0},depth:{value:0},opacity:{value:0},mirror:{value:0}}});
    const aspect=item.video.videoWidth/item.video.videoHeight || 4/3;
    const mesh=new THREE.Mesh(new THREE.PlaneGeometry(.45,.45/aspect,64,48),material);
    mesh.position.z=-.3;mesh.renderOrder=1;this.scene.add(mesh);
    const surface={item,mesh,texture,opacity:0,target:0};this.surfaces.push(surface);return surface;
  }
  remove(item) {
    const surface=this.surfaces.find(s=>s.item===item);if(!surface)return;
    this.scene.remove(surface.mesh);surface.mesh.geometry.dispose();surface.mesh.material.dispose();surface.texture.dispose();
    this.surfaces=this.surfaces.filter(s=>s!==surface);
  }
  updateMask(mask) {
    if(!mask)return;
    if(this.mask.image.width!==mask.width||this.mask.image.height!==mask.height){
      const old=this.mask;
      this.mask=new THREE.DataTexture(mask.bytes,mask.width,mask.height,THREE.RedFormat);
      this.mask.flipY=true;this.mask.unpackAlignment=1;this.mask.minFilter=THREE.LinearFilter;this.mask.magFilter=THREE.LinearFilter;
      this.surfaces.forEach(s=>{s.mesh.material.uniforms.mask.value=this.mask;});old.dispose();
    }else this.mask.image.data=mask.bytes;
    this.mask.needsUpdate=true;
  }
  render({eye,view='window',layout='crossfade',angle=0,cutout=false,maskFresh=false,depth=0.08,mirror=true},seconds) {
    const orbit=view==='orbit';
    if(orbit&&!this.controls.enabled){this.camera.position.set(0,.12,.8);this.controls.target.set(0,0,-.4);}
    this.controls.enabled=orbit;
    if(orbit){this.camera.aspect=this.aspect;this.camera.updateProjectionMatrix();this.controls.update();}
    else applyWindowProjection(this.camera,eye,this.width,this.width/this.aspect);
    this.surfaces.forEach((surface,index)=>{
      const {mesh,item}=surface,u=mesh.material.uniforms;
      surface.target=layout==='array'||index===angle?1:0;
      surface.opacity+=(surface.target-surface.opacity)*(1-Math.exp(-seconds/0.2));
      u.opacity.value=surface.opacity;u.useMask.value=cutout&&maskFresh&&item.live?1:0;
      u.depth.value=depth;u.mirror.value=item.live&&mirror?1:0;
      // Keep mask and mirrored pixels aligned. Geometry uses the same mirrored confidence field.
      u.mask.value=this.mask;
      mesh.visible=surface.opacity>.001;
      mesh.position.x=layout==='array'?(index-(this.surfaces.length-1)/2)*.48:0;
      mesh.rotation.y=layout==='array'?(index-(this.surfaces.length-1)/2)*-.25:0;
    });
    this.renderer.render(this.scene,this.camera);
  }
  dispose() {
    this.resize.disconnect();this.controls.dispose();
    for(const surface of [...this.surfaces])this.remove(surface.item);
    this.scene.traverse(object=>{object.geometry?.dispose();if(object.material){(Array.isArray(object.material)?object.material:[object.material]).forEach(m=>m.dispose());}});
    this.mask.dispose();this.renderer.dispose();this.renderer.forceContextLoss();this.renderer.domElement.remove();
  }
}
