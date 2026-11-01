import {StudioSceneContent} from './scene-content.js';
import * as THREE from '../vendor/three/three.module.js';
import {GLTFLoader} from '../vendor/three/addons/loaders/GLTFLoader.js';
import {applyWindowProjection} from './projection.js';
/** React SpatialFeedPost loadStage adapter. Manifest uses browser Y-up meters. */
export async function loadFeedStage(host,url){
  const response=await fetch(url,{credentials:'same-origin'});if(!response.ok)throw Error('Spatial post unavailable');
  const manifest=await response.json();if(manifest.version!==1||manifest.coordinate_space!=='Y_UP_METERS'||!Array.isArray(manifest.assets)||manifest.assets.length>16)throw Error('Unsupported spatial post');
  const renderer=new THREE.WebGLRenderer({alpha:true,antialias:true});renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.domElement.style.cssText='position:absolute;inset:0;width:100%;height:100%;pointer-events:none';
  const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(45,1,.02,100);scene.add(new THREE.HemisphereLight(0xffffff,0x29304a,2));
  const content=manifest.scene?new StudioSceneContent(scene):null;
  const loader=new GLTFLoader();let disposed=false;const resources=[];
  const disposeObject=object=>object.traverse(node=>{node.geometry?.dispose();for(const material of node.material?(Array.isArray(node.material)?node.material:[node.material]):[]){for(const value of Object.values(material))if(value?.isTexture)value.dispose();material.dispose();}});
  try{
    if(content)await content.load(manifest.scene);
    for(const asset of manifest.assets){
      const parsed=new URL(asset.url,location.origin);if(parsed.origin!==location.origin||!parsed.pathname.startsWith('/api/lightek/'))throw Error('Use an authorized same-origin asset URL');
      for(const key of ['position','scale'])if(!Array.isArray(asset[key])||asset[key].length!==3||asset[key].some(v=>!Number.isFinite(v)||Math.abs(v)>1000))throw Error('Invalid stage transform');
      if(!Array.isArray(asset.quaternion)||asset.quaternion.length!==4||asset.quaternion.some(v=>!Number.isFinite(v)))throw Error('Invalid stage rotation');
      const loaded=await loader.loadAsync(parsed.href);resources.push(loaded.scene);loaded.scene.position.fromArray(asset.position);loaded.scene.quaternion.fromArray(asset.quaternion).normalize();loaded.scene.scale.fromArray(asset.scale);scene.add(loaded.scene);
    }
    host.append(renderer.domElement);const width=Math.max(.15,Math.min(1.5,Number(manifest.window_width_m)||.5));
    const render=(x=0,y=0,z=.6)=>{if(disposed)return;const aspect=Math.max(1,host.clientWidth)/Math.max(1,host.clientHeight);applyWindowProjection(camera,{x,y,z},width,width/aspect);renderer.render(scene,camera);};
    const resize=()=>{renderer.setSize(Math.max(1,host.clientWidth),Math.max(1,host.clientHeight),false);render();};resize();
    return {setEye:render,resize,dispose(){if(disposed)return;disposed=true;content?.dispose();resources.forEach(disposeObject);renderer.dispose();renderer.forceContextLoss();renderer.domElement.remove();}};
  }catch(error){content?.dispose();resources.forEach(disposeObject);renderer.dispose();throw error;}
}
