/* Generative media stays in the production: prompt → local worker → saved asset → edit. */
(() => {
  if(!document.querySelector('#lightek-studio-dashboard'))return;
  const state={request:null,scene:0,loaded:false,loading:false,busy:false,status:null,setup:null,setupDraft:{},images:[],imageNext:null,imagesLoaded:false,jobs:[],error:'',timer:null,drafts:new Map()};
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.ai.'+action,payload:{scene_id:studioCurrentSceneId(),...payload}})).result;
  const active=()=>window.LightekStudioProduction?.mode()==='ai';
  function capture(){const form=app.querySelector('[data-ai-form]');if(form)state.drafts.set(state.scene,Object.fromEntries(new FormData(form)));}
  async function loadImages(before=null,scene=state.scene){
    const result=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{scope_site:true,surface:'ai_input',...(before?{before}:{})}})).result;
    if(scene!==state.scene)return;let images=(result.assets||[]).filter(a=>a.kind==='image'&&a.status==='ready'&&a.proxy_url);const selected=Number(state.drafts.get(scene)?.input_asset_id);if(!before&&Number.isSafeInteger(selected)&&selected>0&&!images.some(a=>a.id===selected)){const extra=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{scope_site:true,asset_ids:[selected]}})).result;images.push(...(extra.assets||[]).filter(a=>a.kind==='image'&&a.status==='ready'&&a.proxy_url));}if(scene!==state.scene)return;state.images=before?[...state.images,...images.filter(a=>!state.images.some(b=>b.id===a.id))]:images;state.imageNext=result.next_before;state.imagesLoaded=true;
  }
  async function refresh(){
    if(state.loading)return;state.loading=true;const scene=state.scene;
    try{
      const [status,jobs,setup]=await Promise.all([call('status'),call('jobs'),call('setup.status')]);
      if(scene!==state.scene)return;if(status?.recipes?.some(r=>r.input_kind==='image')&&!state.imagesLoaded)await loadImages(null,scene);if(scene!==state.scene)return;state.status=status;state.jobs=jobs;state.setup=setup;state.error='';state.loaded=true;
    }catch(error){if(scene===state.scene){state.error=error.message;state.loaded=true;}}
    finally{state.loading=false;if(active()){if(scene===state.scene){capture();repaint();}else queueMicrotask(refresh);}}
    clearTimeout(state.timer);if(active()&&(state.jobs.some(j=>['uploaded','processing'].includes(j.status))||['queued','running'].includes(state.setup?.install?.status)))state.timer=setTimeout(refresh,5000);
  }
  function view(record){
    if(state.scene!==record.scene.id){capture();state.scene=record.scene.id;state.loaded=false;state.status=null;state.setup=null;state.setupDraft={};state.images=[];state.imagesLoaded=false;state.imageNext=null;state.jobs=[];state.error='';clearTimeout(state.timer);}
    if(!state.loaded&&!state.loading)refresh();
    const draft=state.drafts.get(state.scene)||{},status=state.status,ready=(status?.recipes||[]).filter(r=>r.ready),recipe=ready.find(r=>r.id===draft.recipe)||ready[0];
    return `<section class="studio-ai production-panel" aria-label="AI Studio"><header><span class="eb">LIGHTEK / AI STUDIO</span><h2>Imagine it. Make it here.</h2><p>Use saved scenes and characters for CPU production, or an available neural workflow for generated media. Results stay in this production’s library.</p></header><p><a class="vw-btn" href="#/studio/${record.scene.id}/camera" data-production-mode="camera">CPU production settings</a> <a class="vw-btn" href="#/studio/${record.scene.id}/scene" data-production-mode="scene">Model & animate</a></p>${workerSetup()}<div class="ai-layout"><div><form data-ai-form>${draft.shot_id?`<input type="hidden" name="shot_id" value="${E(draft.shot_id)}"><input type="hidden" name="shot_name" value="${E(draft.shot_name||'')}"><p>Storyboard shot: ${E(draft.shot_name||draft.shot_id)}</p>`:''}<label class="fld"><span>What are we creating?</span><select name="recipe" ${ready.length?'':'disabled'}>${ready.map(r=>`<option value="${E(r.id)}" ${r.id===recipe?.id?'selected':''}>${E(r.name)} · ${E(r.kind)}</option>`).join('')||'<option>No ready generation workflows</option>'}</select></label><label class="fld"><span>Describe the shot</span><textarea name="prompt" maxlength="2000" required placeholder="An expressive character in a warmly lit recording studio, cinematic composition…">${E(draft.prompt||'')}</textarea></label>${recipe?.input_kind==='image'?`<label class="fld"><span>Starting image · prepared library still</span><select name="input_asset_id" required><option value="">Choose an image…</option>${state.images.map(a=>`<option value="${a.id}" ${String(a.id)===String(draft.input_asset_id)?'selected':''}>${E(a.name)}</option>`).join('')}</select></label>${state.images.find(a=>String(a.id)===String(draft.input_asset_id))?`<img alt="Starting image" style="max-width:100%;max-height:240px;object-fit:contain" src="${E(state.images.find(a=>String(a.id)===String(draft.input_asset_id)).proxy_url)}">`:''}<p>PNG, JPEG or WebP · up to 10 MB / 16 megapixels. The worker uses a center-cropped still at 1280 × 704 and retains a frozen source reference.</p>${state.imageNext?'<button type="button" class="vw-btn" data-ai="images-more">Load older images</button>':''}`:''}<details><summary>Refine the generation</summary><label class="fld"><span>Avoid in the result</span><textarea name="negative" maxlength="2000">${E(draft.negative||'')}</textarea></label><label class="fld"><span>Installed local model</span><select name="model">${(status?.models||[]).map(m=>`<option ${m===draft.model?'selected':''}>${E(m)}</option>`).join('')||'<option value="">Workflow-managed model</option>'}</select></label><label class="fld"><span>Seed · keep it to repeat a variation</span><input type="number" name="seed" min="0" max="4294967295" step="1" value="${E(draft.seed||Math.floor(Math.random()*4294967296))}"></label></details><button class="vw-btn" ${state.busy||!ready.length?'disabled':''}>${state.busy?'Submitting…':'Generate on my worker'}</button><p role="status">${state.error?E(state.error):state.loading?'Checking your worker…':status?.connected?ready.length?'Local engine connected. No hosted generation API is used.':'Engine connected; its installed nodes or models are not ready for these workflows.':E(status?.reason||'Checking your worker…')}</p><button class="vw-btn" type="button" data-ai="refresh">Check worker & jobs</button></form><aside class="ai-animation"><h3>Character animation</h3><p>Reusable Blender characters, dialogue takes and saved performances belong to the same production. Generated artwork is concept art; it is not automatically a rigged performer.</p><a class="vw-btn" href="#/studio/${record.scene.id}/cast" data-production-mode="cast">Open character direction</a><a class="vw-btn" href="#/studio/${record.scene.id}/stage" data-production-mode="stage">Stage the shot</a><p>The current toon rig and volume-driven mouth controls are basic. Speech analysis and editable mouth cues are available in Cast. Advanced character creation and motion generation remain in development.</p></aside></div><section class="ai-results"><h3>Generation jobs & results</h3>${state.jobs.map(j=>`<article class="ai-result"><header><strong>${E(j.name)}</strong><span>${E(j.status==='uploaded'?'Queued':j.status==='processing'?j.phase:j.status)}</span></header>${j.preview_url?(j.kind==='image'?`<img alt="${E(j.name)}" src="${E(j.preview_url)}">`:['video','audio'].includes(j.kind)?`<${j.kind} controls src="${E(j.preview_url)}"></${j.kind}>`:''):''}<p>${E(j.prompt||'')}</p>${j.input_url?`<a class="vw-btn" href="${E(j.input_url)}" target="_blank" rel="noopener">View saved starting image</a>`:''}<small>Seed ${j.seed??'—'}${j.input_asset_id?` · Starting image #${Number(j.input_asset_id)}`:''}</small>${j.error?`<p role="alert">${E(j.error)}</p>`:''}${j.status==='ready'&&['image','video','audio'].includes(j.kind)?`<button class="vw-btn" data-ai="use" data-id="${j.asset_id}" ${state.busy?'disabled':''}>Add result to edit</button>`:''}</article>`).join('')||'<p>No generations in this production yet. Submit a prompt once a local workflow is ready.</p>'}</section></div></section>`;
  }
  app.addEventListener('input',e=>{if(e.target.closest('[data-ai-form]'))capture();if(e.target.closest('[data-ai-setup]'))state.setupDraft=Object.fromEntries(new FormData(e.target.closest('[data-ai-setup]')));});
  app.addEventListener('change',e=>{const setupForm=e.target.closest('[data-ai-setup]');if(setupForm&&e.target.name==='package_id'){const selected=state.setup.packages.find(p=>p.id===e.target.value),device=setupForm.elements.device;device.querySelector('[value=cpu]').disabled=!selected.devices.includes('cpu');if(!selected.devices.includes(device.value))device.value=selected.devices[0];}if(e.target.closest('[data-ai-form]')){capture();if(['recipe','input_asset_id'].includes(e.target.name))repaint();}if(e.target.closest('[data-ai-setup]'))state.setupDraft=Object.fromEntries(new FormData(e.target.closest('[data-ai-setup]')));});
  app.addEventListener('submit',async e=>{
    const setupForm=e.target.closest('[data-ai-setup]');
    if(setupForm){
      e.preventDefault();if(state.busy)return;
      capture();state.setupDraft=Object.fromEntries(new FormData(setupForm));state.busy=true;state.error='';repaint();
      try{await call('setup.install',state.setupDraft);await refresh();}catch(error){state.error=error.message;}
      finally{state.busy=false;if(active())repaint();}return;
    }
    const form=e.target.closest('[data-ai-form]');if(!form)return;e.preventDefault();if(state.busy)return;capture();const scene=state.scene,draft=state.drafts.get(scene);
    state.busy=true;state.error='';const signature=JSON.stringify([scene,draft]);if(state.request?.signature!==signature)state.request={signature,key:crypto.randomUUID()};const key=state.request.key;render();
    try{await call('generate',{...draft,seed:Number(draft.seed),request_key:key});state.request=null;if(scene===state.scene){state.drafts.set(scene,{...draft,seed:String((Number(draft.seed)+1)%4294967296)});await refresh();}}
    catch(error){state.error=error.message;}
    finally{state.busy=false;if(active())render();}
  });
  app.addEventListener('click',async e=>{
    const button=e.target.closest('[data-ai]');if(!button)return;
    if(button.dataset.ai==='refresh'){capture();state.imagesLoaded=false;await refresh();}
    if(button.dataset.ai==='images-more'&&!state.busy){capture();state.busy=true;try{await loadImages(state.imageNext);}catch(error){state.error=error.message;}finally{state.busy=false;if(active())repaint();}}
    if(button.dataset.ai==='use'&&!state.busy){state.busy=true;button.disabled=true;
      try{await A.studioAssetsReload();LightekStudioTimeline.insert(Number(button.dataset.id));LightekStudioProduction.go('edit',undefined,true);toast('Generated media added to the edit. Save changes to keep the placement.');}
      catch(error){state.error=error.message;toast(error.message);}finally{state.busy=false;}
    }
  });
  window.addEventListener('hashchange',()=>{if(!active()){capture();clearTimeout(state.timer);}});
  function repaint(){
    const focused=app.querySelector(':focus'),name=focused?.name,setup=!!focused?.closest('[data-ai-setup]');
    const start=focused?.selectionStart,end=focused?.selectionEnd;
    render();
    if(name){const target=app.querySelector(`${setup?'[data-ai-setup]':'[data-ai-form]'} [name="${CSS.escape(name)}"]`);target?.focus({preventScroll:true});if(typeof start==='number'&&target?.setSelectionRange)try{target.setSelectionRange(start,end);}catch(_){}}
  }
  function workerSetup(){
    const data=state.setup;if(data?.can_manage===false)return '<aside class="ai-worker"><h3>Optional neural generation</h3><p>Production infrastructure is managed by Lightek. No engine installation is required on your computer. CPU scene production uses the installed Studio runtime; neural generation becomes available when a suitable worker is configured.</p></aside>';if(!Array.isArray(data?.workers)||!Array.isArray(data?.packages))return '';
    const current=data.install||{},working=['queued','running'].includes(current.status),draft=state.setupDraft;
    const selected=data.packages.find(p=>p.id===(draft.package_id||current.package_id))||data.packages[0],gpuOnly=selected&&!selected.devices.includes('cpu');
    const phases={checking_runtime:'Checking server',building_engine:'Building pinned engine',downloading_model:'Downloading verified model',verifying_model:'Checking model checksum',starting_engine:'Starting engine',verifying_engine:'Checking worker connection',ready:'Engine and model files ready'};
    const size=n=>(Number(n)/1073741824).toFixed(2)+' GB';
    return `<details class="ai-worker" ${!state.status?.connected||working?'open':''}><summary>Operator neural-worker setup · ${E(current.status|| (data.active?'configured':'setup'))}</summary>
      <p role="status">${E(current.message||current.progress_message||phases[current.phase]|| (working?'Setup queued on your registered server.':'Install a generation engine and model package on a registered server.'))}</p>
      ${['downloading_model','verifying_model'].includes(current.phase)&&current.total_bytes?`<p>${E(current.model)} · ${size(current.downloaded_bytes)} / ${size(current.total_bytes)}</p><progress aria-label="Model download" value="${Number(current.downloaded_bytes)||0}" max="${Number(current.total_bytes)}"></progress>`:''}
      ${data.workers.length?`<form data-ai-setup><label class="fld"><span>Registered worker</span><select name="installation_id">${data.workers.map(w=>`<option value="${w.id}" ${String(w.id)===String(draft.installation_id||current.installation_id)?'selected':''}>${E(w.domain)}</option>`).join('')}</select></label>
      <label class="fld"><span>Engine & model package</span><select name="package_id">${data.packages.map(p=>`<option value="${E(p.id)}" ${p.id===(draft.package_id||current.package_id)?'selected':''}>${E(p.name)}</option>`).join('')}</select></label>
      <label class="fld"><span>Compute device</span><select name="device"><option value="cpu" ${gpuOnly?'disabled':''}>CPU · concept images</option><option value="cuda" ${gpuOnly||(draft.device||current.device)==='cuda'?'selected':''}>NVIDIA CUDA · images or video</option></select></label>
      <ul>${data.packages.map(p=>`<li>${E(p.name)}: ${p.ram_gib} GB RAM, ${p.free_disk_gib} GB free disk${p.devices.includes('cpu')?'; CPU supported':`; NVIDIA GPU with ${Math.round(p.vram_mib/1024)} GB video memory required`}.</li>`).join('')}</ul>
      <p>Setup checks available memory too. CUDA workers need their NVIDIA driver and container runtime installed. Concept model: CreativeML Open RAIL-M; Wan models: Apache 2.0.</p>
      <button class="vw-btn" ${working||state.busy?'disabled':''}>${working?'Setting up…':current.status==='failed'?'Retry worker setup':'Install engine & models'}</button></form>`:'<p>No registered servers you can manage are available. Register an application runtime in Servers first.</p>'}
      <p>Ready means the engine responds and model files passed verification. Generate and review a sample before production use.</p>
    </details>`;
  }
  function startShot(sceneId,shot){
    capture();
    const previous=state.drafts.get(sceneId)||{};
    state.drafts.set(sceneId,{...previous,prompt:shot.prompt||shot.notes||shot.name,shot_id:shot.id,shot_name:shot.name});
    LightekStudioProduction.go('ai',sceneId,true);
  }
  window.LightekStudioAI={view,startShot,busy:()=>state.busy};
})();
