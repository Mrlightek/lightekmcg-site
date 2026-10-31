import * as THREE from './vendor/three/three.module.js';
import {OrbitControls} from './vendor/three/addons/controls/OrbitControls.js';
import {GLTFLoader} from './vendor/three/addons/loaders/GLTFLoader.js';
const previews=new Map();
function reconcile(){
  for(const [root,state] of previews)if(!root.isConnected){state.renderer.setAnimationLoop(null);state.controls.dispose();state.renderer.dispose();state.scene.traverse(object=>{object.geometry?.dispose();if(object.material){for(const m of Array.isArray(object.material)?object.material:[object.material])m.dispose();}});previews.delete(root);}
  document.querySelectorAll('[data-asset-preview]').forEach(root=>{
    if(previews.has(root))return;
    const scene=new THREE.Scene();scene.background=new THREE.Color('#08080b');const camera=new THREE.PerspectiveCamera(45,Math.max(1,root.clientWidth)/320,.01,10000);
    const renderer=new THREE.WebGLRenderer({antialias:true});renderer.setSize(root.clientWidth||400,320);renderer.setPixelRatio(Math.min(devicePixelRatio,2));root.append(renderer.domElement);
    const controls=new OrbitControls(camera,renderer.domElement);scene.add(new THREE.HemisphereLight(0xffffff,0x444444,3));const light=new THREE.DirectionalLight(0xffffff,3);light.position.set(3,5,4);scene.add(light);
    const state={scene,camera,renderer,controls,mixer:null,clock:new THREE.Clock()};previews.set(root,state);
    new GLTFLoader().setWithCredentials(true).load(root.dataset.assetPreview,gltf=>{
      if(!root.isConnected)return;scene.add(gltf.scene);const bounds=new THREE.Box3().setFromObject(gltf.scene);const center=bounds.getCenter(new THREE.Vector3()),size=bounds.getSize(new THREE.Vector3()).length()||1;
      camera.position.copy(center).add(new THREE.Vector3(size,size*.6,size));camera.far=size*100;camera.updateProjectionMatrix();controls.target.copy(center);controls.update();root.querySelector('[role=status]')?.remove();
      if(gltf.animations.length){state.mixer=new THREE.AnimationMixer(gltf.scene);state.mixer.clipAction(gltf.animations[0]).play();}
    },undefined,error=>{const p=root.querySelector('[role=status]');if(p)p.textContent='Model preview could not load: '+error.message;});
    renderer.setAnimationLoop(()=>{state.mixer?.update(state.clock.getDelta());controls.update();renderer.render(scene,camera);});
  });
}
new MutationObserver(reconcile).observe(document.getElementById('app'),{childList:true,subtree:true});
reconcile();
