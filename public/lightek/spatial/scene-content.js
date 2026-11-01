import * as THREE from '../vendor/three/three.module.js';
import {GLTFLoader} from '../vendor/three/addons/loaders/GLTFLoader.js';

// Adapter from Studio's Blender Z-up scene definitions to this window's Y-up space.
export class StudioSceneContent {
  constructor(scene) {this.scene=scene;this.group=new THREE.Group();this.scene.add(this.group);this.loaded=false;this.generation=0;}
  async load(record) {
    const generation=++this.generation;
    for(const child of [...this.group.children]){this.group.remove(child);child.traverse(object=>{object.geometry?.dispose();if(object.material)(Array.isArray(object.material)?object.material:[object.material]).forEach(material=>{for(const value of Object.values(material))if(value?.isTexture)value.dispose();material.dispose();});});}
    const blender=new THREE.Group();blender.rotation.x=-Math.PI/2;this.group.add(blender);
    const objects=record.objects||[],native=objects.filter(item=>item.object_type==='native_object');
    const addNative=gltf=>{
      if(generation!==this.generation){gltf.scene.traverse(o=>{o.geometry?.dispose();});return;}
      gltf.scene.rotation.x=Math.PI/2;blender.add(gltf.scene);blender.updateMatrixWorld(true);
      const byName=new Map(native.map(item=>[item.definition.blender_object_name,item]));
      const nodes=[];gltf.scene.traverse(node=>{const object=byName.get(node.userData.lightek_object_name||node.name);if(object)nodes.push([node,object]);});
      for(const [node,object] of nodes){
        // Object definitions use Blender world coordinates, as in the main Studio viewport.
        blender.attach(node);apply(node,object.definition);node.visible=!object.definition.native_deleted&&!object.definition.hide_viewport;
        const material=object.definition.material_override;
        if(material)node.traverse(child=>{if(!child.isMesh)return;const originals=Array.isArray(child.material)?child.material:[child.material];child.material=originals.map(original=>{const copy=original.clone();if(material.color)copy.color?.setRGB(...material.color.slice(0,3));if(material.roughness!=null)copy.roughness=material.roughness;if(material.metallic!=null)copy.metalness=material.metallic;return copy;});if(child.material.length===1)child.material=child.material[0];});
      }
    };
    const tasks=[];
    for(const object of objects){
      const d=object.definition||{};if(d.hide_viewport||d.native_deleted)continue;
      if(object.object_type==='imported_asset'&&/^\/api\/lightek\/pwa\/(?:assets\/\d+\/proxy|posts\/\d+\/spatial\/assets\/\d+)$/.test(d.asset_proxy_url||'')){
        tasks.push(new GLTFLoader().setWithCredentials(true).loadAsync(d.asset_proxy_url).then(gltf=>{
          if(d.native_source_preview)addNative(gltf);
          else if(generation===this.generation){const holder=new THREE.Group();gltf.scene.rotation.x=Math.PI/2;holder.add(gltf.scene);apply(holder,d);blender.add(holder);}
        }));
      }else if(['cube','sphere','cylinder','plane'].includes(object.object_type)){
        const geometry=object.object_type==='sphere'?new THREE.SphereGeometry(1,24,16):object.object_type==='cylinder'?new THREE.CylinderGeometry(1,1,2,24):object.object_type==='plane'?new THREE.PlaneGeometry(2,2):new THREE.BoxGeometry(2,2,2);
        if(object.object_type==='cylinder')geometry.rotateX(Math.PI/2);
        const color=d.material?.color||[.3,.6,.7,1];
        const mesh=new THREE.Mesh(geometry,new THREE.MeshStandardMaterial({color:new THREE.Color(...color.slice(0,3)),roughness:d.material?.roughness??.6,metalness:d.material?.metallic??0,side:THREE.DoubleSide,transparent:color[3]<1,opacity:color[3]??1}));
        apply(mesh,d);blender.add(mesh);
      }
    }
    const results=await Promise.allSettled(tasks);
    if(generation!==this.generation)return;
    const count=results.filter(result=>result.status==='rejected').length;
    const bounds=new THREE.Box3().setFromObject(blender);
    if(bounds.isEmpty())throw new Error('This scene has no browser-ready meshes. Prepare its Blender viewport proxy or add a library character first.');
    const center=bounds.getCenter(new THREE.Vector3()),size=bounds.getSize(new THREE.Vector3());
    this.group.scale.setScalar(.35/Math.max(size.x,size.y,size.z,.01));
    blender.position.sub(center);this.group.position.set(0,0,-.5);this.loaded=true;
    return {warnings:count};
  }
  dispose(){this.generation++;this.scene.remove(this.group);this.group.traverse(object=>{object.geometry?.dispose();if(object.material)(Array.isArray(object.material)?object.material:[object.material]).forEach(material=>{for(const value of Object.values(material))if(value?.isTexture)value.dispose();material.dispose();});});}
}
function apply(object,definition){object.position.fromArray(definition.location||[0,0,0]);object.rotation.set(...(definition.rotation||[0,0,0]).map(value=>value*Math.PI/180));object.scale.fromArray(definition.scale||[1,1,1]);}
