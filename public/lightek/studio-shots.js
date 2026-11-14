/* Ordered shot direction shares the existing scene, Cast, render queue and edit. */
(() => {
  if (!document.querySelector('#lightek-studio-dashboard')) return;
  const drafts=new Map();
  const quoteRequests=new Map();
  const state={scene:0,busy:false,loading:false,error:'',timer:null};
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const active=()=>window.LightekStudioProduction?.mode()==='shots';
  const call=async(action,payload)=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const fields=['id','name','notes','prompt','camera_id','frame_start','frame_end','cast_ids'];
  const clean=shot=>Object.fromEntries(fields.map(k=>[k,structuredClone(shot[k])]));
  const draft=()=>drafts.get(state.scene);
  const esc=v=>E(String(v??''));
  const number=(name,label,value)=>`<label><span>${label}</span><input name="${name}" type="number" min="1" max="216000" step="1" required value="${value}"></label>`;
  const button=(action,label,id='',disabled=false)=>`<button type="button" class="vw-btn" data-shot="${action}" data-id="${esc(id)}" ${state.busy||disabled?'disabled':''}>${label}</button>`;

  function capture() {
    const d=draft();if(!d)return;
    for(const form of app.querySelectorAll('[data-shot-form]')) {
      const shot=d.shots.find(s=>s.id===form.dataset.shotForm);if(!shot)continue;
      const data=new FormData(form);
      for(const field of ['name','notes','prompt'])shot[field]=String(data.get(field)||'');
      for(const field of ['camera_id','frame_start','frame_end'])shot[field]=Number(data.get(field));
      shot.cast_ids=data.getAll('cast_ids').map(Number);
    }
  }
  function renderInfo(shot) {
    const saved=draft()?.renders?.[shot.id],r=saved?.render;
    const error=saved?.validation_error;
    return `${error?`<p role="alert">${esc(error)}</p>`:''}${r?`<p class="shot-render-state">Render #${r.operation_id} · ${esc(r.status)}${r.stale?' · Earlier scene revision':''}</p>${r.error?`<p role="alert">${esc(r.error)}</p>`:''}${r.artifacts.map(a=>`<video controls preload="none" aria-label="Rendered ${esc(shot.name)}" src="${esc(a.url)}"></video>`).join('')}${r.status==='completed'&&r.artifacts.length?button('use','Add rendered shot to edit',shot.id,r.stale||!!error):''}`:'<p class="shot-render-state">No render requested for this shot.</p>'}`;
  }
  async function refresh(discard=false) {
    if(state.loading)return;
    const record=current();if(!record)return;
    const id=record.scene.id;state.loading=true;
    try {
      const result=await call('shots.list',{scene_id:id});
      const old=drafts.get(id),renders=Object.fromEntries(result.shots.map(s=>[s.id,s]));
      if(!old||discard||!old.dirty) drafts.set(id,{shots:result.shots.map(clean),renders,lock:result.lock_version,revision:result.revision,dirty:false,request:null});
      else old.renders=renders;
      if(state.scene===id)state.error='';
      if(active()&&state.scene===id) {
        if(!old||discard||!old.dirty)render();
        else for(const row of app.querySelectorAll('[data-shot-render]')) {
          const shot=draft().shots.find(s=>s.id===row.dataset.shotRender);
          if(shot)row.innerHTML=renderInfo(shot);
        }
      }
    } catch(error) {if(state.scene===id){state.error=error.message;if(active())render();}}
    finally {
      state.loading=false;
      if(active()&&current()?.scene.id!==id&&!drafts.has(current()?.scene.id))queueMicrotask(()=>refresh());
    }
    clearTimeout(state.timer);
    if(active()&&Object.values(drafts.get(id)?.renders||{}).some(s=>['pending','running','queued'].includes(s.render?.status)))state.timer=setTimeout(()=>refresh(),5000);
  }
  function view(record) {
    state.scene=record.scene.id;
    if(!draft()&&!state.loading)queueMicrotask(()=>refresh());
    const d=draft(),cameras=record.scene.objects.filter(o=>o.object_type==='camera'&&!o.definition.native_deleted);
    const cast=record.scene.objects.filter(o=>o.definition.character_profile&&!o.definition.native_deleted);
    const fps=Number(record.scene.settings.fps||24)/Number(record.scene.settings.fps_base||1);
    return `<section class="studio-shots production-panel" aria-label="Shots and storyboard"><header><div><span class="eb">LIGHTEK / SHOT DIRECTION</span><h2>Build the sequence.</h2><p>Direct each shot, choose its camera and timing, then render into the same production.</p></div><div class="shot-actions">${button('add','＋ Add shot','',!d||!cameras.length||d.shots.length>=64)}${button('save',d?.dirty?'Save storyboard':'Storyboard saved','',!d||!d.dirty)}${button('refresh',d?.dirty?'Discard draft & reload':'Refresh renders')}</div></header>${!cameras.length?'<p>Add a camera in Camera & lighting to start a shot.</p>':''}${state.error?`<p role="alert">${esc(state.error)}</p>`:''}<p class="shot-board-status" role="status">${state.busy?'Saving your request…':!d?'Loading storyboard…':d.dirty?'Unsaved storyboard changes. Render requests save them first.':`${d.shots.length} shots · saved revision ${d.revision}`}</p><div class="shot-board">${(d?.shots||[]).map((shot,index)=>`<article class="shot-card" data-shot-card="${esc(shot.id)}"><header><strong>SHOT ${String(index+1).padStart(2,'0')}</strong><span>${((shot.frame_end-shot.frame_start+1)/fps).toFixed(2)} seconds</span><div>${button('up','↑',shot.id,index===0)}${button('down','↓',shot.id,index===d.shots.length-1)}${button('duplicate','Duplicate',shot.id)}${button('remove','Remove',shot.id)}</div></header><form data-shot-form="${esc(shot.id)}"><label><span>Shot name</span><input name="name" maxlength="120" required value="${esc(shot.name)}"></label><label><span>Render camera</span><select name="camera_id" required>${cameras.map(c=>`<option value="${c.id}" ${c.id===shot.camera_id?'selected':''}>${esc(c.name)}</option>`).join('')}</select></label><div class="shot-frame-range">${number('frame_start','First frame',shot.frame_start)}${number('frame_end','Last frame',shot.frame_end)}</div><label><span>Direction notes</span><textarea name="notes" maxlength="2000" placeholder="Action, expressions, continuity and sound cues…">${esc(shot.notes)}</textarea></label><details><summary>Cast and Genesis prompt</summary><label><span>Featured placed cast · empty includes everyone</span><select name="cast_ids" multiple size="3">${cast.map(c=>`<option value="${c.id}" ${shot.cast_ids.includes(c.id)?'selected':''}>${esc(c.name)}</option>`).join('')}</select></label><label><span>Generation prompt</span><textarea name="prompt" maxlength="2000" placeholder="Describe a concept or generated shot…">${esc(shot.prompt)}</textarea></label><p>Direction notes stay with the shot. Animation uses the saved scene and performances; generation uses the installed Genesis workflow.</p></details></form><div class="shot-actions">${button('stage','Camera & lighting',shot.id)}${button('generate','Open in Genesis',shot.id)}${button('quote','Review shot render quote',shot.id)}</div><div data-shot-render="${esc(shot.id)}">${renderInfo(shot)}</div></article>`).join('')||(!d?'<p>Loading your saved shots…</p>':'<div class="shot-empty"><h3>Your first shot starts here.</h3><p>Add a shot, select a camera, and set its frame range. Reuse the same scene and cast across the sequence.</p></div>')}</div></section>`;
  }
  async function save() {
    capture();const d=draft(),scene=state.scene;
    if(!d?.dirty)return;
    if([...app.querySelectorAll('[data-shot-form]')].some(f=>!f.reportValidity()))throw Error('Complete the shot fields before saving.');
    const signature=JSON.stringify(d.shots);
    if(d.request?.signature!==signature)d.request={signature,key:crypto.randomUUID()};
    const result=await call('shots.save',{scene_id:scene,lock_version:d.lock,board_revision:d.revision,shots:d.shots,request_key:d.request.key});
    d.lock=result.lock_version;d.revision=result.revision;
    d.dirty=false;d.request=null;
    await A.studioLoad(true);await refresh(true);
  }
  async function run(fn) {
    if(state.busy)return;state.busy=true;state.error='';
    try {await fn();}catch(error){state.error=error.message;toast(error.message);}
    finally {state.busy=false;if(active())render();}
  }
  app.addEventListener('input',event=>{
    if(!event.target.closest('[data-shot-form]'))return;
    capture();draft().dirty=true;
    const status=app.querySelector('.shot-board-status');if(status)status.textContent='Unsaved storyboard changes.';
    const saveButton=app.querySelector('[data-shot=save]');if(saveButton){saveButton.disabled=false;saveButton.textContent='Save storyboard';}
  });
  app.addEventListener('change',event=>{if(event.target.closest('[data-shot-form]'))event.target.dispatchEvent(new Event('input',{bubbles:true}));});
  app.addEventListener('submit',event=>{if(event.target.matches('[data-shot-form]')){event.preventDefault();run(save);}});
  app.addEventListener('click',event=>{
    const b=event.target.closest('[data-shot]');if(!b||state.busy)return;
    const action=b.dataset.shot;capture();const d=draft();
    if(action==='refresh'){run(async()=>{await A.studioLoad(true);await refresh(true);});return;}
    if(!d)return;
    const index=d.shots.findIndex(s=>s.id===b.dataset.id),shot=d.shots[index];
    if(action==='add') {
      const scene=current().scene,camera=scene.objects.find(o=>o.object_type==='camera'&&!o.definition.native_deleted);
      if(!camera||d.shots.length>=64)return;
      const first=Math.max(1,Number(scene.settings.frame_start||1)),fps=Number(scene.settings.fps||24);
      d.shots.push({id:crypto.randomUUID(),name:`Shot ${d.shots.length+1}`,camera_id:camera.id,frame_start:first,frame_end:Math.min(216000,first+Math.min(2400,Math.round(fps*3))-1),cast_ids:[],notes:'',prompt:''});
    } else if(action==='save'){run(save);return;}
    else if(!shot)return;
    else if(action==='remove')d.shots.splice(index,1);
    else if(action==='duplicate'){if(d.shots.length>=64)return;d.shots.splice(index+1,0,{...structuredClone(shot),id:crypto.randomUUID(),name:(shot.name+' copy').slice(0,120)});}
    else if(action==='up'||action==='down') {
      const target=index+(action==='up'?-1:1);if(target<0||target>=d.shots.length)return;
      [d.shots[index],d.shots[target]]=[d.shots[target],d.shots[index]];
    } else {
      run(async()=>{
        await save();
        const saved=draft().shots.find(s=>s.id===shot.id),scene=current().scene;
        if(action==='quote') {
          const signature=JSON.stringify([scene.id,draft().lock,saved]);
          if(!quoteRequests.has(signature))quoteRequests.set(signature,crypto.randomUUID());
          const result=await call('render.quote',{scene_id:scene.id,shot_id:saved.id,output:'movie',lock_version:draft().lock,request_key:quoteRequests.get(signature)});
          LightekStudioApp.setQuote(result);
          LightekStudioProduction.go('deliver',scene.id,true);
        } else if(action==='generate') {
          window.LightekStudioAI?.startShot(scene.id,saved);
        } else if(action==='stage') {
          ST.selectedObjectId=saved.camera_id;LightekStudioProduction.go('camera',scene.id,true);
        } else if(action==='use') {
          const r=draft().renders[saved.id]?.render;
          if(!r||r.stale||r.status!=='completed'||!r.artifacts.length)throw Error('Render the current shot before adding it to the edit.');
          if(LightekStudioTimeline.dirty())await LightekStudioTimeline.save();
          const a=r.artifacts[0],result=await call('artifact.use',{scene_id:scene.id,shot_id:saved.id,artifact_id:a.id,lock_version:current().scene.lock_version,request_key:`shot-edit-${scene.id}-${a.id}`});
          if(result.status!=='ready'){toast(result.error||'Preparing the rendered shot. Choose Add rendered shot to edit again when ready.');return;}
          await A.studioLoad(true);LightekStudioProduction.go('edit',scene.id,true);
        }
      });return;
    }
    d.dirty=true;render();
  });
  window.addEventListener('hashchange',()=>{if(!active()){capture();clearTimeout(state.timer);}});
  window.addEventListener('beforeunload',event=>{if([...drafts.values()].some(d=>d.dirty)){event.preventDefault();event.returnValue='';}});
  window.LightekStudioShots={view,save,busy:()=>state.busy,dirty:()=>!!drafts.get(studioCurrentSceneId())?.dirty};
})();
