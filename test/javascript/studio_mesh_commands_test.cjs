const assert = require('node:assert/strict');
(async () => {
      const THREE = await import('../../public/lightek/vendor/three/three.module.js');
      const { previewMeshCommands, nativeObjectRoot } = await import('../../public/lightek/studio-mesh-commands.js');
      const close = (a,b) => a.every((v,i)=>Math.abs(v-b[i])<1e-5);
      const check = (condition,message) => { if (!condition) throw Error(message); };
      const root = new THREE.Group();
      root.position.set(7,-2,3); root.rotation.set(.3,.5,.8); root.scale.set(2,.75,1.3);
      // Simulate glTF's Y-up mesh coordinates under a Blender Z-up object root.
      const mesh = new THREE.Mesh(new THREE.BufferGeometry().setAttribute('position',new THREE.Float32BufferAttribute([1,3,-2,-1,3,2,0,0,0],3)),new THREE.MeshBasicMaterial());
      mesh.rotation.x=Math.PI/2;root.add(mesh);root.updateWorldMatrix(true,true);
      const point = () => new THREE.Vector3().fromBufferAttribute(mesh.geometry.attributes.position,0).applyMatrix4(mesh.matrix).toArray();
      const original=point();check(close(original,[1,2,3]),'fixture axis conversion');
      for (const axis of ['X','Y','Z']) for (const source_axis of ['X','Y','Z']) {
        if(axis===source_axis) continue;
        const expected=[...original], a='XYZ'.indexOf(axis),s='XYZ'.indexOf(source_axis);
        expected[a]+=.75*expected[s];
        check(previewMeshCommands(root,[{kind:'mesh_skew',axis,source_axis,factor:.75}]).ok,'preview available');
        check(close(point(),expected),'same local geometry as Blender '+axis+source_axis);
        previewMeshCommands(root,[{kind:'mesh_skew',axis,source_axis,factor:.75}]);
        check(close(point(),expected),'slider changes must not accumulate');
      }
      previewMeshCommands(root,[]);check(close(point(),original),'reset restores original');
      previewMeshCommands(root,[{kind:'mesh_skew',axis:'X',source_axis:'Z',factor:.5},{kind:'mesh_skew',axis:'Y',source_axis:'X',factor:-1}]);
      check(close(point(),[2.5,-.5,3]),'saved commands preserve order');
      const unavailable=previewMeshCommands(root,[{kind:'mesh_extrude'}]);
      check(!unavailable.ok&&close(point(),original),'unsupported pending geometry must not fake a preview');
      mesh.isSkinnedMesh=true;
      check(!previewMeshCommands(root,[{kind:'mesh_skew',axis:'X',source_axis:'Z',factor:1}]).ok,'rigged preview needs Blender');
      const imported = new THREE.Mesh(new THREE.BufferGeometry().setAttribute('position',new THREE.Float32BufferAttribute([1,3,-2,0,0,0,0,1,0],3)),new THREE.MeshBasicMaterial());
      imported.rotation.x=Math.PI/2;imported.position.x=4;imported.updateWorldMatrix(true,true);
      const wrapped=nativeObjectRoot(imported,{native_original:{location:[4,0,0]},location:[8,2,1],rotation:[0,0,0],scale:[2,1,1]},imported.matrixWorld.clone());
      wrapped.updateWorldMatrix(true,true);
      const worldPoint=()=>new THREE.Vector3().fromBufferAttribute(imported.geometry.attributes.position,0).applyMatrix4(imported.matrixWorld).toArray();
      check(close(worldPoint(),[10,4,4]),'saved transforms apply after restoring imported object basis');
      previewMeshCommands(wrapped,[{kind:'mesh_skew',axis:'X',source_axis:'Z',factor:.5}]);
      check(close(worldPoint(),[13,4,4]),'skew in native local coordinates survives saved translation and scale');

  assert(true);
  console.log('STUDIO_MESH_COMMANDS_PASS axes reset saved_order gltf_basis transformed_object unsupported_fallback');
})().catch(error=>{console.error(error);process.exitCode=1;});
