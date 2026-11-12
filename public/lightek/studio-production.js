/* Production navigation and handoffs shared by every native Dashboard workspace. */
(() => {
  if (!document.querySelector('#lightek-studio-dashboard')) return;
  const modes = [['stage','Stage'],['edit','Edit'],['cast','Cast'],['music','Music'],['script','Script'],['deliver','Deliver']];
  const aliases = {'3d':'scene',timeline:'edit',performance:'cast',visual:'camera',publish:'deliver'};
  const allowed = new Set([...modes.map(([key])=>key),'scene','camera','assets']);
  const state = {scene:null,hash:null,busy:false,jobs:[],project:null,jobError:'',jobLoading:false,timer:null};
  const selections = new Map();
  const mode = () => { const key=location.hash.split('/')[3]||'stage';return aliases[key]|| (allowed.has(key)?key:'stage'); };
  const current = () => studioSceneRecord(studioCurrentSceneId());
  const call = async(action,payload)=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const busy = () => state.busy || ST.busy || window.LightekStudioMusic?.busy() || window.LightekStudioPerformance?.busy();
  function go(key,sceneId=studioCurrentSceneId(),internal=false) {
    if(busy()&&!internal){toast('Finish the current save or render request before switching.');return;}
    const target=aliases[key]||key;
    if(!allowed.has(target)||!studioSceneRecord(Number(sceneId)))return;
    LightekStudioPerformance?.capture();
    LightekStudioMusic?.stop();LightekStudioTimeline?.stop();
    location.hash=`#/studio/${Number(sceneId)}/${target}`;
  }
  function status() {
    const dirty=[];
    if(LightekStudioApp.dirty())dirty.push('scene notes');
    if(LightekStudioPerformance?.dirty())dirty.push('cast direction');
    if(LightekStudioTimeline?.dirty())dirty.push('edit');
    if(LightekStudioMusic?.dirty(studioCurrentSceneId()))dirty.push('music');
    return dirty.length?'Unsaved '+dirty.join(', '):'Changes saved';
  }
  function updateStatus() {
    const el=app.querySelector('[data-production-status]');if(el)el.textContent=status();
  }
  function header(record) {
    const scene=record.scene,scenes=studioSceneRecords().filter(r=>r.project.id===record.project.id);
    return `<header class="production-header"><a class="production-brand" href="#/studio">LIGHTEK<span>STUDIO</span></a><div class="production-title"><a href="#/studio" class="production-breadcrumb">Productions</a><h1>${E(record.project.name)}</h1></div><label class="production-scene"><span>Scene</span><select aria-label="Production scene" data-production-scene>${scenes.map(r=>`<option value="${r.scene.id}" ${r.scene.id===scene.id?'selected':''}>${E(r.scene.name)}</option>`).join('')}</select></label><span class="production-save" role="status" data-production-status>${E(status())}</span><button class="vw-btn" data-production="save">Save changes</button></header><div class="production-toolbar"><nav aria-label="Production workspaces">${modes.map(([key,label])=>`<a href="#/studio/${scene.id}/${key}" data-production-mode="${key}">${label}</a>`).join('')}</nav><div class="production-tools"><a href="#/studio/${scene.id}/assets" data-production-mode="assets">Assets</a><button class="vw-btn" data-vw="save-template">Save show template</button></div></div><div class="production-context"><div><strong data-production-mode-title></strong><span data-production-description></span></div><nav aria-label="Scene tools"><a href="#/studio/${scene.id}/scene" data-production-mode="scene">Model & animate</a><a href="#/studio/${scene.id}/camera" data-production-mode="camera">Camera & lighting</a></nav></div>`;
  }
  const descriptions = {
    stage:['Stage your scene','Cast, sets and camera share this scene with your edit.'],
    edit:['Shape the episode','Cut picture, mix dialogue and music, finish color and add titles.'],
    cast:['Direct your cast','Save performances, render shots, then add completed shots to the edit below.'],
    music:['Score the episode','Keep the musical source editable; add or update its mix in this scene’s edit.'],
    script:['Write the scene','Your script, shot notes and continuity stay with this production.'],
    deliver:['Finish and release','Review completed renders and export or publish the production.'],
    scene:['Build and animate','Select an object to model, sculpt, rig, animate or edit its nodes.'],
    camera:['Compose the shot','Camera, lighting and render settings for this scene.'],
    assets:['Production assets','Import and reuse media, characters and Blender sources.']
  };
  function panel(record,key) {
    const ui=LightekStudioApp;
    ST.workspaceMode=({stage:'3d',scene:'3d',camera:'visual',edit:'timeline',cast:'performance',deliver:'publish'})[key]||key;
    ui.prepare(record);
    if(key!=='cast')LightekStudioPerformance?.leave?.();
    if(key==='stage')return LightekStudioVisual.view(record);
    if(key==='music')return LightekStudioMusic.view(record);
    if(key==='assets')return `<div class="production-panel studio-dashboard-advanced">${R.studio('library')}</div>`;
    let content;
    if(key==='scene')content=`<div class="studio-work-grid"><section>${ui.outliner?.(record.scene)||''}</section><aside>${ui.inspector(record.scene)}</aside></div>${ui.tools(record)}`;
    else if(key==='camera')content=`<div class="production-camera-layout"><aside>${ui.outliner?.(record.scene)||''}</aside><div>${ui.visual(record)}</div></div>`;
    else if(key==='deliver')content=ui.delivery(record,'publish');
    else if(key==='script')content=ui.story(record,'script')+`<details><summary>Shot notes</summary>${ui.story(record,'storyboard')}</details>`;
    else content=ui.story(record,ST.workspaceMode);
    return `<section class="production-panel studio-dashboard-advanced">${content||''}</section>`;
  }
  function renderProduction(id) {
    const record=studioSceneRecord(Number(id));if(!record)return false;
    // Browser history can also change the route during a request; keep its context pinned.
    if(state.hash&&location.hash!==state.hash&&busy()){
      history.replaceState(null,'',location.pathname+location.search+state.hash);
      toast('Finish the current operation before switching.');return true;
    }
    LightekStudioPerformance?.capture();
    const key=mode();
    if(state.scene!==record.scene.id){
      if(state.scene)selections.set(state.scene,ST.selectedObjectId);
      ST.selectedObjectId=selections.get(record.scene.id)||null;
      state.scene=record.scene.id;
    }
    const changedProject=state.project!==record.project.id;
    if(changedProject){state.project=record.project.id;state.jobs=[];state.jobError='';clearTimeout(state.timer);}
    const html=panel(record,key);
    let shell=app.querySelector('[data-production-shell]');
    if(!shell){app.innerHTML='<section class="production-workspace" data-production-shell><div data-production-heading></div><div data-production-content></div><details class="production-jobs" data-production-jobs><summary>Renders & handoffs <span data-production-job-count></span></summary><div data-production-job-list></div></details></section>';shell=app.querySelector('[data-production-shell]');}
    const heading=shell.querySelector('[data-production-heading]');
    if(heading.dataset.scene!==String(record.scene.id)){heading.innerHTML=header(record);heading.dataset.scene=record.scene.id;}
    shell.dataset.mode=key;
    heading.querySelector('[data-production=save]').hidden=!['edit','music','script'].includes(key);
    heading.querySelectorAll('[data-production-mode]').forEach(el=>{const selected=el.dataset.productionMode===key;if(selected)el.setAttribute('aria-current','page');else el.removeAttribute('aria-current');});
    heading.querySelector('[data-production-mode-title]').textContent=descriptions[key][0];
    heading.querySelector('[data-production-description]').textContent=descriptions[key][1];
    shell.querySelector('[data-production-content]').innerHTML=html;
    shell.querySelectorAll('a[href="#/studio/library"]').forEach(a=>a.href=`#/studio/${record.scene.id}/assets`);
    shell.querySelectorAll('a[href^="#/create"]').forEach(a=>a.hidden=true);
    shell.querySelectorAll('[data-vw=advanced]').forEach(b=>b.textContent='Model & animate');
    state.hash=location.hash;updateStatus();renderJobs();
    return true;
  }
  function renderJobs() {
    const el=app.querySelector('[data-production-job-list]');if(!el)return;
    const count=app.querySelector('[data-production-job-count]');if(count)count.textContent=state.jobs.length?`· ${state.jobs.length}`:'';
    el.innerHTML=`<div class="production-job-toolbar"><p>Finished shots move into the same scene’s edit. Draft previews stay marked as previews.</p><button class="vw-btn" data-production="refresh-jobs" ${state.jobLoading?'disabled':''}>${state.jobLoading?'Checking…':'Refresh renders'}</button></div>${state.jobError?`<p role="alert">${E(state.jobError)}</p>`:''}${state.jobs.map(job=>`<article class="production-job"><div><strong>${job.type==='edit_media'?'Episode master':'Scene render'} #${job.id}</strong><span>${E(job.status)}${job.draft_preview?' · Draft preview':''}</span>${job.error?`<p role="alert">${E(job.error)}</p>`:''}</div><div>${job.artifacts.map(a=>`<div class="production-artifact"><a href="${E(a.url)}" target="_blank" rel="noopener">${E(a.filename)}</a>${job.status==='completed'&&!job.draft_preview&&['video','audio','image','preview'].includes(a.kind)?`<button class="vw-btn" data-production="use-render" data-artifact="${a.id}">Add to edit</button>`:''}</div>`).join('')}</div></article>`).join('')||'<p class="production-job-empty">No renders loaded. Refresh to check this production.</p>'}`;
  }
  async function loadJobs() {
    if(state.jobLoading)return;const project=state.project;state.jobLoading=true;renderJobs();
    try{const result=await call('operations.list',{project_id:project});if(project!==state.project)return;state.jobs=result.operations;state.jobError='';}
    catch(error){if(project===state.project)state.jobError=error.message;}
    finally{state.jobLoading=false;renderJobs();}
    clearTimeout(state.timer);
    if(app.querySelector('[data-production-jobs]')?.open&&state.jobs.some(j=>['pending','running','queued'].includes(j.status)))state.timer=setTimeout(loadJobs,8000);
  }
  async function useRender(button) {
    if(busy())return;const record=current(),scene=record.scene;state.busy=true;button.disabled=true;
    try{
      if(LightekStudioTimeline.dirty())await LightekStudioTimeline.save();
      const result=await call('artifact.use',{scene_id:scene.id,artifact_id:Number(button.dataset.artifact),lock_version:scene.lock_version,request_key:`render-edit-${scene.id}-${button.dataset.artifact}`});
      if(result.status!=='ready'){toast(result.status==='failed'?result.error:'Preparing this shot for editing. Choose Add to edit again to check.');return;}
      scene.lock_version=result.lock_version;scene.settings.timeline=result.timeline;LightekStudioTimeline.set(result.timeline);
      await A.studioAssetsReload();
      toast('Shot added to the episode edit.');state.busy=false;go('edit');
    }catch(error){toast(error.message);}finally{state.busy=false;button.disabled=false;updateStatus();}
  }
  app.addEventListener('click',event=>{
    const link=event.target.closest('[data-production-mode]');if(link){event.preventDefault();go(link.dataset.productionMode);return;}
    const button=event.target.closest('[data-production]');if(!button)return;
    const action=button.dataset.production;
    if(action==='refresh-jobs')loadJobs();
    if(action==='use-render')useRender(button);
    if(action==='save'){
      if(busy())return;const key=mode();
      const save=key==='music'?()=>LightekStudioMusic.save():key==='edit'?()=>LightekStudioTimeline.save():()=>LightekStudioApp.save();
      state.busy=true;button.disabled=true;Promise.resolve().then(save).then(()=>{updateStatus();toast('Changes saved.');}).catch(error=>toast(error.message)).finally(()=>{state.busy=false;button.disabled=false;});
    }
  });
  app.addEventListener('change',event=>{if(event.target.matches('[data-production-scene]')){go(mode(),Number(event.target.value));if(busy())event.target.value=state.scene;}queueMicrotask(updateStatus);});
  app.addEventListener('input',()=>queueMicrotask(updateStatus));
  app.addEventListener('toggle',event=>{if(event.target.matches('[data-production-jobs]')){if(event.target.open)loadJobs();else clearTimeout(state.timer);}},true);
  window.addEventListener('beforeunload',event=>{if(LightekStudioApp.hasDrafts()||LightekStudioTimeline?.hasDrafts()||LightekStudioPerformance?.hasDrafts()){event.preventDefault();event.returnValue='';}});
  window.LightekStudioProduction={render:renderProduction,go,mode};
})();
