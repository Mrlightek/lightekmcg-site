/* Built-in procedural authoring and reusable native Blender sources. */
(() => {
  const ui=window.LightekStudioApp,esc=value=>E(String(value??''));
  const call=async(action,payload)=>(await nevaeh.execute({capability:'studio.workspace.blender.'+action,payload})).result;
  let recipes=[],loading=false,error='',saveKey=null;
  const studio=R.studio;
  const options=()=>studioSceneRecords().map(({scene,project})=>`<option value="${scene.id}">${esc(project.name)} · ${esc(scene.name)}</option>`).join('');
  async function load(){if(loading||recipes.length)return;loading=true;try{const data=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{}})).result;recipes=data.creation_recipes||[];if(!recipes.length)throw Error('Studio creation needs the latest application update and migrations.');error='';}catch(e){error=e.message;}finally{loading=false;if(location.hash==='#/studio/workshop')render(1);}}
  R.studio=id=>{
    if(id!=='workshop'||!meProfile()||!ST.loaded)return studio(id);
    if(!loading&&!recipes.length&&!error)load();
    return `<main class="wrap pwa-page studio-create"><span class="eb">LIGHTEK MEDIA OS / ASSET WORKSHOP</span><h1>Create in Studio.</h1><p>Build editable shapes, sets, stages, lights and animated effects with the built-in Blender engine. No provider account or API key required.</p><div class="pwa-post-actions"><a class="btn" href="#/studio">Productions</a><a class="btn" href="#/studio/library">Blender files & media</a><a class="btn" href="/dashboard/studio-broadcasting">Control room</a><a class="btn" href="/dashboard/live">Live Studio</a></div>${error?`<p role="alert">${esc(error)}</p>`:''}${loading?'<p role="status">Loading creation tools…</p>':''}<div class="g3">${recipes.map(item=>`<article class="pwa-post"><span class="eb">${esc(item.category)}</span><h2>${esc(item.name)}</h2><p>${item.category==='effects'?'Animated Blender geometry with editable parts and keyframes.':item.category==='sets'?'Build a set from separate editable objects.':'Create real editable scene elements.'}</p><form data-studio-create-form data-recipe="${esc(item.key)}"><label class="fld"><span>Name</span><input name="name" required maxlength="120" value="${esc(item.name)}"></label><label class="fld"><span>Destination</span><select name="scene_id"><option value="">New production with cameras & lights</option>${options()}</select></label><label class="fld"><span>Size multiplier</span><input name="size" type="number" min="0.01" max="100" step="0.01" value="1" required></label>${item.category==='lights'?'':`<label class="fld"><span>Surface color</span><input name="color" type="color" value="#508bb8"></label><label class="fld"><span>Roughness</span><input name="roughness" type="number" min="0" max="1" step="0.05" value="0.5" required></label><label class="fld"><span>Metallic</span><input name="metallic" type="number" min="0" max="1" step="0.05" value="0" required></label>`}<button class="btn p">Create & open 3D workspace</button><p role="status" data-create-status></p></form></article>`).join('')}</div><section class="pwa-post"><h2>Bring your Blender work with you.</h2><p>Import .blend and .glb files, open native objects in the Outliner, and edit transforms, materials, lighting and exposed Geometry Nodes values. Save a scene as a reusable Blender asset from its workspace toolbar.</p><a class="btn p" href="#/studio/library">Open asset browser</a><p>Freeform mesh sculpting, rig construction and shader node wiring still use the Blender desktop editor. Import the edited source to continue here. These built-in recipes create procedural assets; they do not perform text-to-3D AI inference.</p></section></main>`;
  };
  const tools=ui.tools;
  ui.tools=record=>tools(record)+`<div class="pwa-post-actions"><a class="btn sm" href="#/studio/workshop">Create shapes, sets & effects</a><button class="btn sm" data-a="studioSaveNativeAsset">Save scene as Blender asset</button><a class="btn sm" href="/dashboard/live">Open Live Studio</a></div>`;
  A.studioSaveNativeAsset=async button=>{
    const record=studioSceneRecord(studioCurrentSceneId());if(!record)return toast('Open a saved scene first.');
    const key=record.scene.id+':'+record.scene.lock_version;if(saveKey?.key!==key)saveKey={key,requestKey:crypto.randomUUID()};
    button.disabled=true;
    try{await call('asset.save',{scene_id:record.scene.id,lock_version:record.scene.lock_version,name:record.scene.name,request_key:saveKey.requestKey});toast('Blender asset save queued. Follow its status in Blender files.');location.hash='#/studio/library';await A.studioAssetsReload();}
    catch(e){toast(e.message);}finally{button.disabled=false;}
  };
  app.addEventListener('submit',async event=>{
    const form=event.target.closest('[data-studio-create-form]');if(!form)return;event.preventDefault();if(form.dataset.busy)return;
    form.dataset.busy='true';const button=form.querySelector('button'),notice=form.querySelector('[data-create-status]');button.disabled=true;notice.textContent='Creating editable scene…';
    const record=studioSceneRecord(Number(form.elements.scene_id.value));
    try{const result=await call('create',{recipe:form.dataset.recipe,name:form.elements.name.value,size:Number(form.elements.size.value),color:form.elements.color?.value||'#ffffff',roughness:Number(form.elements.roughness?.value??0.5),metallic:Number(form.elements.metallic?.value??0),scene_id:record?.scene.id,lock_version:record?.scene.lock_version,request_key:form.dataset.requestKey||=crypto.randomUUID()});await A.studioLoad(true);ST.workspaceMode='3d';ST.selectedObjectId=result.object_id;location.hash='#/studio/'+result.scene_id;render(1);toast('Your editable asset is ready in the 3D workspace.');}
    catch(e){notice.textContent=e.message;toast(e.message);}finally{delete form.dataset.busy;button.disabled=false;}
  });
})();
