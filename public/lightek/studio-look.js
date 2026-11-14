/* Explicit saved shader inputs and scene compositor parameters over Blender. */
(() => {
 if(!document.querySelector('#lightek-studio-dashboard'))return;
 const states=new Map();let currentId=null,busy=false;
 const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
 const state=id=>{if(!states.has(id))states.set(id,{data:null,attempted:false,loading:false,error:'',selected:0,drafts:{},dirty:new Set(),requests:{},preview:null,polling:false,timer:null});return states.get(id);};
 const active=id=>window.LightekStudioProduction?.mode()==='look'&&studioCurrentSceneId()===id;
 const targetKey=target=>target?'material:'+JSON.stringify([target.object_id,target.target,target.slot]):'material';
 const shown=(value,min,max,step)=>Number((Math.round((Math.max(min,Math.min(max,Number(value)))-min)/step)*step+min).toFixed(5));
 function capture(){
   const s=states.get(currentId);if(!s||s.suppressCapture)return;
   for(const form of app.querySelectorAll('[data-look-form]')){if(form.querySelector('fieldset')?.disabled)continue;s.drafts[form.dataset.lookKey||'scene']=Object.fromEntries(new FormData(form));}
 }
 async function load(id){const s=state(id);if(s.loading)return;s.loading=true;s.attempted=true;s.suppressCapture=true;
   try{s.data=await call('look.status',{scene_id:id});s.error='';}catch(error){s.error=error.message;}
   finally{s.loading=false;for(const key of Object.keys(s.drafts))if(!s.dirty.has(key))delete s.drafts[key];if(active(id))render(1);s.suppressCapture=false;}
 }
 const defaults={exposure:0,gamma:1,saturation:1,contrast:0,blur:0,glow:0,glow_threshold:1};
 const controls={exposure:['Exposure · stops',-5,5,.1],gamma:['Gamma',.1,3,.05],saturation:['Saturation',0,2,.05],contrast:['Contrast',-100,100,1],blur:['Blur · pixels',0,20,1],glow:['Glow',0,1,.05],glow_threshold:['Glow threshold',0,10,.1]};
 const surfaces={metallic:['Metallic',0,1,.05],roughness:['Roughness',0,1,.05],transmission:['Transmission',0,1,.05],ior:['Refraction index',1,3,.05],opacity:['Opacity',0,1,.05],emission_strength:['Emission strength',0,20,.1]};
 const linear=v=>v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);
 const hex=color=>'#'+color.slice(0,3).map(v=>Math.max(0,Math.min(1,v))).map(v=>Math.round(255*(v<=.0031308?12.92*v:1.055*Math.pow(v,1/2.4)-.055)).toString(16).padStart(2,'0')).join('');
 const rgba=(value,alpha=1)=>value.slice(1).match(/../g).map(v=>linear(parseInt(v,16)/255)).concat(alpha);
 const E2=v=>E(String(v??''));
 function fields(spec,values,draft={}){return Object.entries(spec).map(([name,[label,min,max,step]])=>{
   const initial=shown(values[name],min,max,step),value=draft[name]??initial;
   return `<label class="fld"><span>${E2(label)} <output data-look-output="${name}">${E2(draft[name]??values[name])}</output></span><input type="range" name="${name}" min="${min}" max="${max}" step="${step}" value="${E2(value)}" data-initial="${initial}"></label>`;
 }).join('');}

 function view(record){
   if(currentId!==record.scene.id){capture();currentId=record.scene.id;}
   const s=state(currentId);if(!s.data&&!s.loading&&!s.attempted)load(currentId);
   if(s.data&&s.data.lock_version!==record.scene.lock_version&&!s.dirty.size&&!busy&&!s.loading&&s.refreshVersion!==record.scene.lock_version){s.refreshVersion=record.scene.lock_version;load(currentId);}
   if(s.preview&&['pending','running'].includes(s.preview.status)&&!s.polling&&!s.timer)s.timer=setTimeout(()=>poll(currentId,s.preview.operation_id),1000);
   if(s.preview)s.preview.stale=s.preview.native_revision!==(record.scene.settings?.native_revision||0);
   const look=s.data?.look||defaults,target=s.data?.targets?.[s.selected],draft=s.drafts[targetKey(target)]||{};
   return `<section class="studio-look"><header><span class="eb">LIGHTEK / LOOK & MATERIALS</span><h2>Shape the surface. Finish the shot.</h2><p>Apply saves Blender parameters. Preview renders the saved scene; completed shot renders use the same settings.</p></header>${s.error?`<p role="alert">${E2(s.error)}</p>`:''}<div class="look-grid"><section><h3>Scene finish</h3><form data-look-form="scene"><fieldset ${busy||s.loading||!s.data?'disabled':''}>${fields(controls,look,s.drafts.scene)}<div class="look-actions"><button class="vw-btn">Apply scene finish</button><button type="button" class="vw-btn" data-look="reset-scene">Reset scene finish</button></div></fieldset></form><p>The finish follows your scene’s existing compositor. Reset removes Studio’s finish and restores its original image connection.</p></section><section><h3>Materials</h3><label class="fld"><span>Object / mesh / material slot</span><select data-look-target ${busy||s.loading?'disabled':''}>${(s.data?.targets||[]).map((item,index)=>`<option value="${index}" ${index===s.selected?'selected':''}>${E2(item.name)} · slot ${item.slot}</option>`).join('')||'<option>No editable materials in this scene</option>'}</select></label>${target?`<form data-look-form="material" data-look-key="${E2(targetKey(target))}"><fieldset ${busy||s.loading?'disabled':''}><label class="fld"><span>Surface color</span><input type="color" name="color" value="${E2(draft.color||hex(target.values.color))}" data-initial="${hex(target.values.color)}"></label>${fields(Object.fromEntries(Object.entries(surfaces).filter(([name])=>!target.fields||target.fields.includes(name))),target.values,draft)}${!target.fields||target.fields.includes('emission_color')?`<label class="fld"><span>Emission color</span><input type="color" name="emission_color" value="${E2(draft.emission_color||hex(target.values.emission_color))}" data-initial="${hex(target.values.emission_color)}"></label>`:''}<div class="look-actions"><button class="vw-btn">Apply material changes</button><button type="button" class="vw-btn" data-look="reset-material">Reset this material</button></div></fieldset></form><p>${target.linked_fields.length?'Linked inputs: '+target.linked_fields.map(E2).join(', ')+'. ':''}Only changed inputs are overridden. Editing a linked input replaces its texture or animation connection. Reset restores the saved source settings.</p>`:'<p>Add a primitive, import a native scene or place a Cast character with Principled materials.</p>'}</section></div><footer class="look-actions"><button class="vw-btn" data-look="preview" ${busy||s.loading||!s.data?'disabled':''}>Render saved look preview</button><button class="vw-btn" data-look="reload" ${busy||s.loading?'disabled':''}>Reload saved settings</button><span role="status">${s.loading?'Loading saved settings…':s.preview?'Preview: '+E2(s.preview.status)+(s.preview.stale?' · scene changed; request a new preview.':''):'Use Apply to save each group before previewing.'}</span></footer>${s.preview?.url&&!s.preview.stale?`<img class="look-preview" alt="Saved Blender scene look" src="${E2(s.preview.url)}">`:''}</section>`;
 }
 async function poll(id,operationId){const s=state(id);s.timer=null;if(!active(id)||s.polling)return;s.polling=true;
   try{s.preview=await call('blender.preview',{scene_id:id,operation_id:operationId});capture();if(active(id))render(1);if(active(id)&&['pending','running'].includes(s.preview.status))s.timer=setTimeout(()=>poll(id,operationId),2500);}
   catch(error){s.error=error.message;if(active(id))render(1);}
   finally{s.polling=false;}
 }
 async function save(kind,reset=false,chosenKey=null){
   if(busy)return;capture();const id=currentId,s=state(id),target=chosenKey?s.data.targets.find(item=>targetKey(item)===chosenKey):s.data.targets[s.selected],group=kind==='scene'?'scene':targetKey(target);let payload={scene_id:id,lock_version:s.data.lock_version,operation:reset?'reset':'apply'};
   if(kind==='scene')payload.look=Object.fromEntries(Object.entries(s.drafts.scene||{}).map(([key,value])=>[key,Number(value)]));
   else{if(!target)return;payload={...payload,object_id:target.object_id,target:target.target,slot:target.slot,values:{}};
     if(!reset)for(const [name,value] of Object.entries(s.drafts[group]||{})){
       const color=['color','emission_color'].includes(name),initial=color?hex(target.values[name]):String(shown(target.values[name],...surfaces[name].slice(1)));
       if(color?String(value)!==initial:Number(value)!==Number(initial))payload.values[name]=color?rgba(value,target.values[name][3]):Number(value);
     }
   }
   const signature=JSON.stringify([kind,payload]);if(s.requests[group]?.signature!==signature)s.requests[group]={signature,key:crypto.randomUUID()};payload.request_key=s.requests[group].key;
   busy=true;s.error='';render(1);
   try{await call(kind==='scene'?'look.save':'material.save',payload);if(s.preview)s.preview.stale=true;delete s.requests[group];delete s.drafts[group];s.dirty.delete(group);await load(id);await A.studioLoad(true);toast('Appearance saved. Render a preview to review it.');}
   catch(error){s.error=error.message;}
   finally{busy=false;if(active(id))render(1);}
   return !s.error;
 }
 app.addEventListener('input',event=>{const form=event.target.closest('[data-look-form]');if(!form)return;capture();const s=state(currentId);s.dirty.add(form.dataset.lookKey||'scene');const output=form.querySelector(`[data-look-output="${event.target.name}"]`);if(output)output.textContent=event.target.value;});
 app.addEventListener('change',event=>{if(!event.target.matches('[data-look-target]'))return;capture();const s=state(currentId);s.selected=Number(event.target.value);render(1);});
 app.addEventListener('submit',event=>{const form=event.target.closest('[data-look-form]');if(!form)return;event.preventDefault();save(form.dataset.lookForm);});
 app.addEventListener('click',async event=>{const button=event.target.closest('[data-look]');if(!button||busy)return;const action=button.dataset.look,id=currentId,s=state(id);
   if(action==='reset-scene')return save('scene',true);if(action==='reset-material')return save('material',true);
   if(action==='reload'){s.drafts={};s.dirty.clear();s.requests={};const pending=load(id);render(1);await pending;return;}
   if(action==='preview'){busy=true;s.error='';capture();render(1);try{s.preview=await call('blender.preview',{scene_id:id});clearTimeout(s.timer);s.timer=setTimeout(()=>poll(id,s.preview.operation_id),2500);}catch(error){s.error=error.message;}finally{busy=false;if(active(id))render(1);}}
 });
 queueMicrotask(()=>{if(window.LightekStudioProduction?.mode()==='look'&&typeof studioSceneRecord==='function'&&studioSceneRecord(studioCurrentSceneId()))render(1);});
 window.LightekStudioLook={view,hasDrafts:()=>[...states.values()].some(s=>s.dirty.size),busy:()=>busy,capture,dirty:(id=studioCurrentSceneId())=>!!states.get(id)?.dirty.size,save:async()=>{capture();const s=state(currentId);for(const group of [...s.dirty])if(!await save(group==='scene'?'scene':'material',false,group==='scene'?null:group))throw Error(s.error);}};
})();
