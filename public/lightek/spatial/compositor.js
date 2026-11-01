import {createServerDepthLayer} from './server-depth.js';
import * as THREE from '../vendor/three/three.module.js';
import {OrbitControls} from '../vendor/three/addons/controls/OrbitControls.js';
import {applyWindowProjection} from './projection.js';

const vertexShader = `
  uniform sampler2D depthMap; uniform float useDepth; uniform float depth; uniform float mirror;
  varying vec2 videoUV;
  void main() {
    videoUV = uv;
    vec3 displaced = position;
    displaced.z += texture2D(depthMap, vec2(mix(uv.x, 1.0 - uv.x, mirror), uv.y)).r * useDepth * depth;
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
    this.serverLayer=createServerDepthLayer();this.serverSequence=0;this.serverMode=false;this.serverGeneration=0;
    this.scene = new THREE.Scene(); this.scene.background = new THREE.Color('#101825');this.scene.add(this.serverLayer.mesh);
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
    this.depthMap=new THREE.DataTexture(new Uint8Array([0]),1,1,THREE.RedFormat);this.depthMap.needsUpdate=true;this.hasDepth=false;
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
      uniforms:{video:{value:texture},mask:{value:this.mask},depthMap:{value:this.depthMap},useDepth:{value:0},useMask:{value:0},depth:{value:0},opacity:{value:0},mirror:{value:0}}});
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
      this.mask=new THREE.DataTexture(mask.bytes,mask.width,mask.height,THREE.RedFormat,mask.bytes instanceof Float32Array?THREE.FloatType:THREE.UnsignedByteType);
      this.mask.flipY=true;this.mask.unpackAlignment=1;this.mask.minFilter=THREE.LinearFilter;this.mask.magFilter=THREE.LinearFilter;
      this.surfaces.forEach(s=>{s.mesh.material.uniforms.mask.value=this.mask;});old.dispose();
    }else this.mask.image.data=mask.bytes;
    this.mask.needsUpdate=true;
  }
  async updateServerFrame(metadata,bitmap) {
    if(!bitmap)return false;
    const generation=this.serverGeneration;const source=metadata.depth;
    if(!source||source.frame_id!==metadata.frame_id||source.encoding!=='zlib-f32le'||source.origin!=='bottom-left'||source.range!=='opengl_0_1'){bitmap.close();return false;}
    const sequence=Number(metadata.sequence);if(sequence<=this.serverSequence){bitmap.close();return false;}
    const width=source.width,height=source.height;
    if(!Number.isInteger(width)||!Number.isInteger(height)||width<1||width>160||height<1||height>90||source.data.length>48000){bitmap.close();return false;}
    try{
      const compressed=Uint8Array.from(atob(source.data),c=>c.charCodeAt(0));
      const reader=new Blob([compressed]).stream().pipeThrough(new DecompressionStream('deflate')).getReader();let count=0;const chunks=[];
      while(true){const {value,done}=await reader.read();if(done)break;count+=value.length;if(count>width*height*4){await reader.cancel();throw Error('Depth packet exceeded its dimensions');}chunks.push(value);}
      if(count!==width*height*4)throw Error('Depth size mismatch');const bytes=new Uint8Array(count);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
      const data=new DataView(bytes.buffer),values=new Float32Array(width*height);for(let i=0;i<values.length;i++)values[i]=data.getFloat32(i*4,true);
      if(generation!==this.serverGeneration||sequence<=this.serverSequence||!this.host.isConnected){bitmap.close();return false;}
      this.serverLayer.update({bitmap,depthValues:values,width,height,colorFrameId:metadata.frame_id,depthFrameId:source.frame_id,camera:this.camera,projectionMatrix:metadata.projection_matrix,viewMatrix:metadata.view_matrix});
      this.serverSequence=sequence;this.serverMode=true;return true;
    }catch(error){bitmap.close();throw error;}
  }
  clearServerFrame(){this.serverGeneration++;this.serverMode=false;this.serverSequence=0;this.serverLayer.hide();this.camera.matrixAutoUpdate=true;this.scene.children.forEach(object=>{if(object!==this.serverLayer.mesh)object.visible=true;});}
  updateDepthMap({bytes,width,height}) {
    if(!(bytes instanceof Float32Array)||bytes.length!==width*height)throw Error('Use a separate normalized estimated-depth map');
    if(bytes.some(v=>!Number.isFinite(v)||v<0||v>1))throw Error('Depth values must be normalized to 0–1');
    this.depthMap.dispose();this.depthMap=new THREE.DataTexture(bytes,width,height,THREE.RedFormat,THREE.FloatType);
    this.depthMap.flipY=true;this.depthMap.unpackAlignment=1;this.depthMap.needsUpdate=true;this.hasDepth=true;
    this.surfaces.forEach(s=>{s.mesh.material.uniforms.depthMap.value=this.depthMap;});
  }
  render({eye,view='window',layout='crossfade',angle=0,cutout=false,maskFresh=false,depth=0.08,mirror=true},seconds) {
    const orbit=view==='orbit';
    if(!this.serverMode&&orbit&&!this.controls.enabled){this.camera.position.set(0,.12,.8);this.controls.target.set(0,0,-.4);}
    this.controls.enabled=orbit&&!this.serverMode;
    if(this.serverMode){this.scene.children.forEach(object=>{if(object!==this.serverLayer.mesh&&!this.surfaces.some(surface=>surface.mesh===object))object.visible=false;});}
    else if(orbit){this.camera.aspect=this.aspect;this.camera.updateProjectionMatrix();this.controls.update();}
    else applyWindowProjection(this.camera,eye,this.width,this.width/this.aspect);
    this.surfaces.forEach((surface,index)=>{
      const {mesh,item}=surface,u=mesh.material.uniforms;
      surface.target=layout==='array'||index===angle?1:0;
      surface.opacity+=(surface.target-surface.opacity)*(1-Math.exp(-seconds/0.2));
      u.opacity.value=surface.opacity;u.useMask.value=cutout&&maskFresh&&item.live?1:0;
      u.depth.value=depth;u.useDepth.value=this.hasDepth&&item.live?1:0;u.mirror.value=item.live&&mirror?1:0;
      // Confidence controls alpha only. Relief requires a separate depth estimator.
      u.mask.value=this.mask;
      mesh.visible=surface.opacity>.001;
      if(this.serverMode){
        const distance=2,projection=this.camera.projectionMatrix.elements,aspect=item.video.videoWidth/item.video.videoHeight||4/3;
        const height=2*distance/Math.abs(projection[5])*.8,width=height*aspect;
        mesh.matrixAutoUpdate=false;mesh.matrix.copy(this.camera.matrixWorld).multiply(new THREE.Matrix4().makeTranslation(0,0,-distance)).multiply(new THREE.Matrix4().makeScale(width/.45,height/(.45/aspect),1));
        mesh.visible=item.live&&surface.opacity>.001;u.opacity.value=1;
      }else{mesh.matrixAutoUpdate=true;mesh.position.z=-.3;
      mesh.position.x=layout==='array'?(index-(this.surfaces.length-1)/2)*.48:0;
      mesh.rotation.y=layout==='array'?(index-(this.surfaces.length-1)/2)*-.25:0;}
    });
    this.renderer.render(this.scene,this.camera);
  }
  dispose() {
    this.serverGeneration++;this.resize.disconnect();this.controls.dispose();this.serverLayer.dispose();
    for(const surface of [...this.surfaces])this.remove(surface.item);
    this.scene.traverse(object=>{object.geometry?.dispose();if(object.material){(Array.isArray(object.material)?object.material:[object.material]).forEach(m=>m.dispose());}});
    this.mask.dispose();this.depthMap.dispose();this.renderer.dispose();this.renderer.forceContextLoss();this.renderer.domElement.remove();
  }
}
