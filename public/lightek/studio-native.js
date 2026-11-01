/* Native Blender authoring over pinned .blend scenes. */
(() => {
  const ui=window.LightekStudioApp;
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const esc=v=>E(String(v??''));
  const call=async(action,payload)=>(await nevaeh.execute({capability:'studio.workspace.blender.'+action,payload})).result;
  const run=fn=>Promise.resolve().then(fn).catch(error=>toast(error.message));
  const input=(key,label,value,type='number')=>`<label class="fld"><span>${esc(label)}</span><input name="${esc(key)}" type="${type}" ${type==='number'?'step="any"':''} value="${esc(value)}"></label>`;
  let preview={},lastScene=null;
  const prepare=ui.prepare;
  ui.prepare=record=>{prepare(record);if(lastScene!==record.scene.id){lastScene=record.scene.id;if(record.scene.settings?.native_blender_asset_id&&['production','scene'].includes(ST.workspaceMode))ST.workspaceMode='3d';}};
  const isNative=object=>object?.definition?.native_original&&object.definition.blender_object_name;
  async function save(object,properties={},operation='save',name=null){
    const record=current();if(!record||!object)throw Error('Select a native Blender object first.');
    const result=await call('object.save',{scene_id:record.scene.id,object_id:object.id,lock_version:record.scene.lock_version,properties,operation,name});
    ST.selectedObjectId=operation==='delete'?null:result.object_id;if(result.object){const index=record.scene.objects.findIndex(item=>item.id===result.object.id);if(index<0)record.scene.objects.push(result.object);else record.scene.objects[index]=result.object;record.scene.lock_version=result.lock_version;record.scene.object_count=record.scene.objects.length;}else await A.studioLoad(true);render(1);return result;
  }
  const originalInspector=ui.inspector;
  ui.inspector=scene=>{
    const object=studioWorkspaceSelectedObject(scene);if(object?.definition?.native_source_preview)return `<aside class="studio-workspace-inspector-shell"><h3>Blender viewport proxy</h3><p>Select an object in the Blender Outliner to edit the native scene.</p></aside>`;if(!isNative(object))return originalInspector(scene);
    const d=object.definition,material=d.materials?.length?{...d.materials[0],...(d.material_override||{})}:null;
    const color=(material?.color||[.55,.58,.65,1]).slice(0,3).map(v=>Math.round(v*255).toString(16).padStart(2,'0')).join('');
    return `<aside class="studio-workspace-inspector-shell studio-native-inspector"><span class="eb">Blender object properties</span><h3>${esc(object.name)}</h3><p>${esc(d.native_type||'CAMERA')} · ${esc(d.blender_object_name)}</p><form data-native-object-form>${input('name','Name',object.name,'text')}${['location','rotation','scale'].map(key=>`<fieldset><legend>${esc(key)}</legend><div class="pwa-vector">${['X','Y','Z'].map((axis,i)=>input(`${key}_${i}`,axis,d[key]?.[i]??(key==='scale'?1:0))).join('')}</div></fieldset>`).join('')}<label><input type="checkbox" name="hide_render" ${d.hide_render?'checked':''}> Hide in Blender renders</label><label><input type="checkbox" name="hide_viewport" ${d.hide_viewport?'checked':''}> Hide in viewport</label>${d.native_type==='LIGHT'?input('energy','Light power',d.energy??1000)+input('size','Light size',d.size??1)+input('light_color','Light color','#'+(d.color||[1,1,1]).map(v=>Math.round(v*255).toString(16).padStart(2,'0')).join(''),'color'):''}${material&&material.editable!==false?`<fieldset><legend>Material · ${esc(d.materials?.[0]?.name||'Surface')}</legend>${input('material_color','Base color','#'+color,'color')}${input('metallic','Metallic',material.metallic??0)}${input('roughness','Roughness',material.roughness??.5)}</fieldset>`:''}${d.node_inputs?.length?`<fieldset><legend>Geometry Nodes inputs</legend>${d.node_inputs.map((socket,index)=>socket.type==='NodeSocketBool'?`<label><input name="node_${index}" type="checkbox" ${socket.value?'checked':''}> ${esc(socket.name)}</label>`:input(`node_${index}`,`${socket.modifier} · ${socket.name}`,socket.value)).join('')}</fieldset>`:''}<button class="btn p sm">Save Blender object</button><p role="status" data-native-object-status></p></form><div class="pwa-post-actions"><button class="btn sm" data-a="studioNativeDuplicate">Duplicate object</button><button class="btn sm" data-a="studioNativeDelete">Remove from scene</button>${object.object_type==='camera'?'<button class="btn sm" data-a="studioWorkspaceMode" data-mode="visual">Lens & camera settings</button>':''}</div><details><summary>Native modifiers & collections</summary><p>${(d.collections||[]).map(esc).join(' · ')||'Scene collection'}</p>${(d.modifiers||[]).map(mod=>`<p>${esc(mod.name)} · ${esc(mod.type)}</p>`).join('')||'<p>No modifiers.</p>'}</details></aside>`;
  };
  ui.outliner=scene=>{
    if(!scene.settings?.native_blender_asset_id)return null;
    const objects=(scene.objects||[]).filter(object=>!object.definition?.native_source_preview&&!object.definition?.native_deleted);
    const removed=(scene.objects||[]).filter(object=>object.definition?.native_deleted);
    const groups=new Map();for(const object of objects){const key=object.definition?.collections?.[0]||'Scene collection';if(!groups.has(key))groups.set(key,[]);groups.get(key).push(object);}
    return `<section class="studio-semantic-graph" aria-label="Blender Outliner"><h3>Scene collection</h3><small>${objects.length} editable objects · native Blender source</small>${[...groups].map(([name,items])=>`<details open><summary>${esc(name)} · ${items.length}</summary>${items.map(object=>`<div class="studio-semantic-element ${Number(ST.selectedObjectId)===object.id?'on':''}"><button class="studio-semantic-label" data-a="studioSelectObject" data-id="${object.id}"><span>${object.object_type==='camera'?'◎':object.definition?.native_type==='LIGHT'?'☼':'◇'}</span><span><b>${esc(object.name)}</b><small>${esc(object.definition?.native_type||object.object_type)}${object.definition?.parent_name?' · parent: '+esc(object.definition.parent_name):''}</small></span></button>${isNative(object)?`<button class="studio-semantic-eye" data-a="studioNativeVisibility" data-id="${object.id}" aria-label="${object.definition.hide_viewport?'Show':'Hide'} ${esc(object.name)}">${object.definition.hide_viewport?'◌':'◉'}</button>`:''}</div>`).join('')}</details>`).join('')}${removed.length?`<details><summary>Removed objects · ${removed.length}</summary>${removed.map(object=>`<p>${esc(object.name)} <button class="btn sm" data-a="studioNativeRestore" data-id="${object.id}">Restore object</button></p>`).join('')}</details>`:''}</section>`;
  };
  A.studioNativeDuplicate=()=>run(()=>save(studioWorkspaceSelectedObject(current()?.scene),{},'duplicate'));
  A.studioNativeDelete=()=>run(()=>save(studioWorkspaceSelectedObject(current()?.scene),{},'delete'));
  A.studioNativeRestore=button=>run(()=>save(current()?.scene.objects.find(item=>item.id===Number(button.dataset.id)),{},'restore'));
  A.studioNativeVisibility=button=>run(()=>{const object=current()?.scene.objects.find(item=>item.id===Number(button.dataset.id));return save(object,{hide_viewport:!object.definition.hide_viewport});});
  for(const [action,replacement] of [['studioDuplicateObject','studioNativeDuplicate'],['studioDeleteObject','studioNativeDelete']]){
    const previous=A[action];A[action]=(...args)=>{const object=studioWorkspaceSelectedObject(current()?.scene);if(object?.definition?.native_source_preview)return toast('Select a native object in the Blender Outliner.');return isNative(object)?A[replacement](...args):previous?.(...args);};
  }
  const tools=ui.tools;
  ui.tools=record=>`${tools(record)}<section class="pwa-post studio-blender-preview"><div class="pwa-post-actions"><b>Blender frame preview</b><label>Frame <input type="number" data-blender-preview-frame value="${Number(record.scene.settings?.frame_current||1)}" min="${Number(record.scene.settings?.frame_start||1)}" max="${Number(record.scene.settings?.frame_end||250)}" style="width:100px"></label><button class="btn p sm" data-a="studioBlenderDraftPreview">Render draft frame</button><button class="btn sm" data-a="studioWorkspaceMode" data-mode="3d">Layout</button><button class="btn sm" data-a="studioWorkspaceMode" data-mode="visual">Camera & render settings</button><a class="btn sm" href="#/studio/library">Blender Asset Browser</a></div><p>Draft previews use Blender at up to 320 pixels. Full exports use the render workflow.</p><p role="status">${esc(preview[record.scene.id]?.message||'Ready to preview the active camera.')}</p>${preview[record.scene.id]?.url?`<img src="${esc(preview[record.scene.id].url)}" alt="Blender draft camera render" style="max-width:100%;max-height:320px">`:''}</section>`;
  A.studioBlenderDraftPreview=()=>run(async()=>{
    const record=current();if(!record)return;
    const frame=Number(app.querySelector('[data-blender-preview-frame]')?.value||record.scene.settings?.frame_current||1);
    preview[record.scene.id]={message:'Blender is rendering this frame…'};render(1);
    let result=await call('preview',{scene_id:record.scene.id,frame});
    const update=async()=>{
      if(['pending','running'].includes(result.status)){
        preview[record.scene.id]={message:'Blender is rendering this frame…'};
        setTimeout(()=>run(async()=>{result=await call('preview',{scene_id:record.scene.id,operation_id:result.operation_id});await update();}),2000);
      }else{preview[record.scene.id]={message:result.status==='completed'?`Blender draft ready · frame ${result.frame??frame}.`:result.error||'Blender preview failed.',url:result.url};}
      if(current()?.scene.id===record.scene.id)render(1);
    };await update();
  });
  app.addEventListener('submit',event=>{
    const form=event.target.closest('[data-native-object-form]');if(!form)return;event.preventDefault();
    run(async()=>{
      const object=studioWorkspaceSelectedObject(current()?.scene),d=object.definition;
      const properties={};for(const key of ['location','rotation','scale'])properties[key]=[0,1,2].map(i=>Number(form.elements[`${key}_${i}`].value));
      for(const key of ['hide_render','hide_viewport'])properties[key]=form.elements[key].checked;
      for(const key of ['energy','size'])if(form.elements[key])properties[key]=Number(form.elements[key].value);
      if(form.elements.light_color){const hex=form.elements.light_color.value;properties.color=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255);}
      if(form.elements.material_color){const base={...d.materials[0],...(d.material_override||{})},hex=form.elements.material_color.value,originalHex='#'+base.color.slice(0,3).map(v=>Math.round(v*255).toString(16).padStart(2,'0')).join(''),material={};if(hex!==originalHex)material.color=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255).concat(base.color[3]??1);for(const key of ['metallic','roughness'])if(Math.abs(Number(form.elements[key].value)-Number(base[key]||0))>0.000001)material[key]=Number(form.elements[key].value);if(Object.keys(material).length)properties.material=material;}
      properties.node_inputs=(d.node_inputs||[]).map((socket,i)=>({modifier:socket.modifier,identifier:socket.identifier,value:socket.type==='NodeSocketBool'?form.elements[`node_${i}`].checked:Number(form.elements[`node_${i}`].value)}));
      await save(object,properties,'save',form.elements.name.value);toast('Native Blender object saved');
    }).catch(error=>{form.querySelector('[data-native-object-status]').textContent=error.message;});
  });
  if(window.LightekStudioViewportBridge){
    const snapshot=LightekStudioViewportBridge.snapshot,commit=LightekStudioViewportBridge.commitTransform;
    LightekStudioViewportBridge.snapshot=()=>{const state=snapshot();return state?{...state,settings:current()?.scene.settings||{}}:state;};
    LightekStudioViewportBridge.commitTransform=(id,properties)=>{const object=current()?.scene.objects.find(item=>item.id===Number(id));if(object?.definition?.native_source_preview)throw Error('Select a native object in the Blender Outliner.');return isNative(object)?save(object,properties):commit(id,properties);};
  }
})();
