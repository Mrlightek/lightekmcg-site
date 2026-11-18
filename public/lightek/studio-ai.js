/* Generative media stays in the production: prompt → local worker → saved asset → edit. */
(() => {
  if(!document.querySelector('#lightek-studio-dashboard'))return;
  const state={request:null,scene:0,loaded:false,loading:false,busy:false,status:null,setup:null,setupDraft:{},images:[],imageNext:null,imagesLoaded:false,jobs:[],error:'',timer:null,drafts:new Map(),selectedJob:null,performanceAssets:[],performanceNext:null,performanceLoaded:false,performanceDraft:{}};
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.ai.'+action,payload:{scene_id:studioCurrentSceneId(),...payload}})).result;
  const active=()=>['ai','workflows'].includes(window.LightekStudioProduction?.mode());
  function capture(){const form=app.querySelector('[data-ai-form]');if(form)state.drafts.set(state.scene,Object.fromEntries(new FormData(form)));}
  async function loadImages(before=null,scene=state.scene){
    const result=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{scope_site:true,surface:'ai_input',...(before?{before}:{})}})).result;
    if(scene!==state.scene)return;let images=(result.assets||[]).filter(a=>a.kind==='image'&&a.status==='ready'&&a.proxy_url);const selected=Number(state.drafts.get(scene)?.input_asset_id);if(!before&&Number.isSafeInteger(selected)&&selected>0&&!images.some(a=>a.id===selected)){const extra=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{scope_site:true,asset_ids:[selected]}})).result;images.push(...(extra.assets||[]).filter(a=>a.kind==='image'&&a.status==='ready'&&a.proxy_url));}if(scene!==state.scene)return;state.images=before?[...state.images,...images.filter(a=>!state.images.some(b=>b.id===a.id))]:images;state.imageNext=result.next_before;state.imagesLoaded=true;
  }
  async function loadPerformanceAssets(before=null,scene=state.scene){
    const result=(await nevaeh.execute({capability:'studio.workspace.assets.list',payload:{scope_site:true,surface:'ai_performance',...(before?{before}:{})}})).result;
    if(scene!==state.scene)return;
    const assets=result.assets||[];
    state.performanceAssets=before?[...state.performanceAssets,...assets.filter(a=>!state.performanceAssets.some(b=>b.id===a.id))]:assets;
    state.performanceNext=result.next_before;state.performanceLoaded=true;
  }
  function capturePerformance(){
    const form=app.querySelector('[data-ai-performance]');
    if(form)state.performanceDraft=Object.fromEntries(new FormData(form));
  }
  async function refresh(){
    if(state.loading)return;state.loading=true;const scene=state.scene;
    try{
      const [status,jobs,setup]=await Promise.all([call('status'),call('jobs'),call('setup.status')]);
      if(scene!==state.scene)return;if(status?.recipes?.some(r=>r.input_kind==='image')&&!state.imagesLoaded)await loadImages(null,scene);if(scene!==state.scene)return;if(status?.performances?.some(item=>item.configured)&&!state.performanceLoaded)await loadPerformanceAssets(null,scene);if(scene!==state.scene)return;state.status=status;state.jobs=jobs;state.setup=setup;state.error='';state.loaded=true;
    }catch(error){if(scene===state.scene){state.error=error.message;state.loaded=true;}}
    finally{state.loading=false;if(active()){if(scene===state.scene){capture();capturePerformance();repaint();}else queueMicrotask(refresh);}}
    clearTimeout(state.timer);if(active()&&(state.jobs.some(j=>['uploaded','processing'].includes(j.status))||['queued','running'].includes(state.setup?.install?.status)))state.timer=setTimeout(refresh,5000);
  }
  const jobState=job=>job.status==='uploaded'?'Queued':job.status==='processing'?(job.phase||'Processing').replaceAll('_',' '):job.status;
  const selectedJob=()=>state.jobs.find(job=>job.asset_id===state.selectedJob)||state.jobs.find(job=>job.preview_url)||state.jobs[0];
  const gigabytes=bytes=>(bytes/1073741824).toFixed(1);
  function workerInfo(){
    const status=state.status,device=status?.device,install=state.setup?.install;
    const connected=status?.connected;
    return `<section class="ai-card ai-worker-status"><h3>Generation worker</h3>
      <dl><dt>ComfyUI</dt><dd data-health="${connected?'ready':'waiting'}">${!state.loaded?'Checking…':connected?'Connected':'Unavailable'}</dd>
      <dt>Device</dt><dd>${E(({cuda:'NVIDIA CUDA',cpu:'CPU',mps:'Apple Metal',xpu:'Intel XPU'})[device?.type]||'Unavailable')}</dd>
      <dt>VRAM</dt><dd>${device?.vram_total?`${gigabytes(device.vram_free)} / ${gigabytes(device.vram_total)} GB free`:device?.type==='cpu'?'CPU worker':'Unavailable'}</dd></dl>
      <button type="button" class="vw-btn" data-ai="refresh">Refresh worker</button>
      <details><summary>Worker activity</summary>
        ${install?.status?`<p>${E(install.message||install.progress_message||install.phase||install.status)}</p>`:''}
        ${state.jobs.slice(0,6).map(job=>`<p><strong>${E(jobState(job))}</strong> · ${E(job.name)}${job.error?`<br>${E(job.error)}`:''}</p>`).join('')||'<p>No generation activity yet.</p>'}
      </details></section>`;
  }
  function preview(job){
    const output=job?.preview_url;
    return `<section class="ai-card ai-player"><header><h3>Preview</h3>${job?`<span>${E(jobState(job))}</span>`:''}</header>
      <div class="ai-monitor">${output?(job.kind==='video'? `<video aria-label="Generated video preview" controls playsinline preload="metadata" src="${E(output)}"></video>`:job.kind==='image'?`<img alt="${E(job.name)}" src="${E(output)}">`:job.kind==='audio'?`<audio controls src="${E(output)}"></audio>`:'<p>Open the result in the media library.</p>'):`<p>${job?'The preview will appear when this job finishes.':'Generate a shot to preview it here.'}</p>`}</div>
      ${job?`<footer><strong>${E(job.name)}</strong>${job.status==='ready'&&output?`<button class="vw-btn" data-ai="use" data-id="${job.asset_id}" ${state.busy?'disabled':''}>Add result to edit</button>`:''}</footer>`:''}</section>`;
  }
  function historyPanel(job){
    return `<section class="ai-card ai-history"><h3>Prompt history</h3>
      ${state.jobs.length?`<div class="ai-history-list">${state.jobs.map(item=>`<button type="button" data-ai="select-job" data-id="${item.asset_id}" aria-pressed="${item===job}"><span>${E(item.name)}</span><small>${E(jobState(item))}</small></button>`).join('')}</div>`:'<p>No previous prompts.</p>'}
      ${job?`<dl><dt>Prompt</dt><dd>${E(job.prompt||job.name)}</dd><dt>Seed</dt><dd>${E(job.seed??'—')}</dd><dt>Steps</dt><dd>${E(job.steps??'—')}</dd></dl>${job.input_url?`<a href="${E(job.input_url)}" target="_blank" rel="noopener">Starting image</a>`:''}${job.error?`<p role="alert">${E(job.error)}</p>`:''}`:''}</section>`;
  }
  function performancePanel(){
    const engines=state.status?.performances;
    if(!engines?.length)return '';
    const ready=engines.filter(engine=>engine.configured),draft=state.performanceDraft;
    const selected=ready.find(engine=>engine.id===draft.recipe)||ready[0];
    const options=(kinds,selectedId)=>state.performanceAssets.filter(asset=>kinds.includes(asset.kind)).map(asset=>`<option value="${asset.id}" ${String(asset.id)===selectedId?'selected':''}>${E(asset.name)}</option>`).join('');
    const driverLabel=selected?.driver==='audio'?'Dialogue recording':selected?.id==='facefusion'?'Target performance':'Driving performance';
    return `<section class="ai-card ai-performance"><h3>Performance tools</h3>
      <ul>${engines.map(engine=>`<li><strong>${E(engine.name)}</strong> · ${E(engine.action)} <small>${engine.configured?'Worker configured':'Worker setup required'}</small></li>`).join('')}</ul>
      ${selected?`<form data-ai-performance><label class="fld"><span>Performance workflow</span><select name="recipe">${ready.map(engine=>`<option value="${E(engine.id)}" ${engine===selected?'selected':''}>${E(engine.name)}</option>`).join('')}</select></label>
      <label class="fld"><span>Source portrait or footage</span><select name="input_asset_id" required><option value="">Choose from the media library</option>${options(selected.source,draft.input_asset_id)}</select></label>
      <label class="fld"><span>${driverLabel}</span><select name="driver_asset_id" required><option value="">Choose from the media library</option>${options([selected.driver],draft.driver_asset_id)}</select></label>
      <p>Use prepared library media. Recordings and footage can run up to 15 seconds.</p>
      ${state.performanceNext?'<button class="vw-btn" type="button" data-ai="performance-more">Load older media</button>':''}
      <button class="vw-btn primary" ${state.busy?'disabled':''}>Generate performance</button></form>`:'<p>An operator needs to configure a performance worker.</p>'}</section>`;
  }
  function view(record,mode='ai'){
    if(state.scene!==record.scene.id){capture();state.scene=record.scene.id;state.loaded=false;state.status=null;state.setup=null;state.setupDraft={};state.images=[];state.imagesLoaded=false;state.imageNext=null;state.jobs=[];state.selectedJob=null;state.performanceAssets=[];state.performanceLoaded=false;state.performanceNext=null;state.performanceDraft={};state.error='';clearTimeout(state.timer);}
    if(!state.loaded&&!state.loading)refresh();
    const draft=state.drafts.get(state.scene)||{},status=state.status,recipes=status?.recipes||[],ready=recipes.filter(r=>r.ready);
    const eligible=mode==='ai'?ready.filter(r=>r.kind==='video'):ready;
    const recipe=eligible.find(r=>r.id===draft.recipe)||eligible[0],job=selectedJob();
    const input=state.images.find(image=>String(image.id)===String(draft.input_asset_id));
    const seed=draft.seed??Math.floor(Math.random()*4294967296);
    const steps=draft.steps??recipe?.steps;
    const message=state.error||(!state.loaded?'Checking worker…':eligible.length?'':status?.reason||'No workflows are ready for this mode. Check Workflows for availability.');
    return `<section class="studio-ai production-panel" aria-label="${mode==='workflows'?'Workflows':'AI Studio'}">
      <header class="ai-heading"><h2>${mode==='workflows'?'Workflows':'Generate video'}</h2></header>
      <div class="ai-desk"><div class="ai-main">
      <div class="ai-layout">
        <form class="ai-card ai-controls" data-ai-form>
          <h3>${mode==='workflows'?'Workflow parameters':'Shot setup'}</h3>
          ${draft.shot_id?`<input type="hidden" name="shot_id" value="${E(draft.shot_id)}"><input type="hidden" name="shot_name" value="${E(draft.shot_name||'')}"><p>Storyboard shot · ${E(draft.shot_name||draft.shot_id)}</p>`:''}
          <label class="fld"><span>Workflow</span><select name="recipe" ${eligible.length?'':'disabled'}>${eligible.map(r=>`<option value="${E(r.id)}" ${r.id===recipe?.id?'selected':''}>${E(r.name)}</option>`).join('')||'<option>No ready workflows</option>'}</select></label>
          <label class="fld"><span>Prompt</span><textarea name="prompt" maxlength="2000" required placeholder="Describe the subject, action, and camera angle">${E(draft.prompt||'')}</textarea></label>
          ${recipe?.input_kind==='image'?`<label class="fld"><span>Starting image</span><select name="input_asset_id" required><option value="">Choose a library still</option>${state.images.map(a=>`<option value="${a.id}" ${a===input?'selected':''}>${E(a.name)}</option>`).join('')}</select></label>${input?`<img class="ai-input-preview" alt="Starting image" src="${E(input.proxy_url)}">`:''}${state.imageNext?'<button type="button" class="vw-btn" data-ai="images-more">Load older images</button>':''}`:''}
          ${Number.isInteger(recipe?.steps)?`<label class="fld"><span>Sampling steps <output data-ai-step-value>${E(steps)}</output></span><input type="range" name="steps" min="1" max="60" step="1" value="${E(steps)}"></label>`:''}
          <details ${mode==='workflows'?'open':''}><summary>Generation parameters</summary>
            <label class="fld"><span>Negative prompt</span><textarea name="negative" maxlength="2000">${E(draft.negative||'')}</textarea></label>
            ${recipe?.kind==='image'?`<label class="fld"><span>Checkpoint</span><select name="model">${(status?.models||[]).map(model=>`<option ${model===draft.model?'selected':''}>${E(model)}</option>`).join('')||'<option value="">Workflow-managed model</option>'}</select></label>`:''}
            <label class="fld"><span>Seed</span><input type="number" name="seed" min="0" max="4294967295" step="1" value="${E(seed)}"></label>
          </details>
          <button class="vw-btn primary" ${state.busy||!recipe?'disabled':''}>${state.busy?'Submitting…':'Generate'}</button>
          ${message?`<p role="status">${E(message)}</p>`:''}
        </form>
        ${preview(job)}
      </div>
      ${mode==='workflows'?`<section class="ai-card ai-recipes"><h3>Workflow availability</h3>${recipes.map(r=>`<div><strong>${E(r.name)}</strong><span>${E(r.ready?'Ready':r.reason||'Unavailable')}</span></div>`).join('')||'<p>Connect a generation worker to load its workflows.</p>'}</section>${performancePanel()}${workerSetup()}`:''}
      </div><aside class="ai-inspector" aria-label="Generation inspector">
        ${workerInfo()}
        ${historyPanel(job)}
        <section class="ai-card"><h3>Export</h3>${window.LightekStudioDelivery?.settings(LightekStudioTimeline.get())||''}<a class="vw-btn" href="#/studio/${record.scene.id}/deliver">Export settings</a></section>
      </aside></div></section>`;
  }
  app.addEventListener('input',e=>{if(e.target.closest('[data-ai-form]')){
      capture();
      if(e.target.name==='steps')app.querySelector('[data-ai-step-value]').textContent=e.target.value;
    }if(e.target.closest('[data-ai-setup]'))state.setupDraft=Object.fromEntries(new FormData(e.target.closest('[data-ai-setup]')));});
  app.addEventListener('change',e=>{const setupForm=e.target.closest('[data-ai-setup]');if(setupForm&&e.target.name==='package_id'){const selected=state.setup.packages.find(p=>p.id===e.target.value),device=setupForm.elements.device;device.querySelector('[value=cpu]').disabled=!selected.devices.includes('cpu');if(!selected.devices.includes(device.value))device.value=selected.devices[0];}if(e.target.closest('[data-ai-form]')){capture();if(e.target.name==='recipe'){
      const draft=state.drafts.get(state.scene);
      delete draft.model;delete draft.steps;delete draft.input_asset_id;
    }
    if(['recipe','input_asset_id'].includes(e.target.name))repaint();}if(e.target.closest('[data-ai-setup]'))state.setupDraft=Object.fromEntries(new FormData(e.target.closest('[data-ai-setup]')));});
  app.addEventListener('change',e=>{
    if(!e.target.closest('[data-ai-performance]'))return;
    capturePerformance();
    if(e.target.name==='recipe'){
      delete state.performanceDraft.input_asset_id;delete state.performanceDraft.driver_asset_id;
      repaint();
    }
  });
  app.addEventListener('submit',async e=>{
    const performance=e.target.closest('[data-ai-performance]');
    if(performance){
      e.preventDefault();if(state.busy)return;
      capture();capturePerformance();const draft=state.performanceDraft;
      const signature=JSON.stringify([state.scene,draft]);
      if(state.request?.signature!==signature)state.request={signature,key:crypto.randomUUID()};
      state.busy=true;state.error='';repaint();
      try{
        const result=await call('generate',{...draft,request_key:state.request.key});
        state.selectedJob=result.asset_id;state.request=null;
        await refresh();
      }catch(error){state.error=error.message;}
      finally{state.busy=false;if(active())repaint();}
      return;
    }
    const setupForm=e.target.closest('[data-ai-setup]');
    if(setupForm){
      e.preventDefault();if(state.busy)return;
      capture();state.setupDraft=Object.fromEntries(new FormData(setupForm));state.busy=true;state.error='';repaint();
      try{await call('setup.install',state.setupDraft);await refresh();}catch(error){state.error=error.message;}
      finally{state.busy=false;if(active())repaint();}return;
    }
    const form=e.target.closest('[data-ai-form]');if(!form)return;e.preventDefault();if(state.busy)return;capture();const scene=state.scene,draft=state.drafts.get(scene);
    state.busy=true;state.error='';const signature=JSON.stringify([scene,draft]);if(state.request?.signature!==signature)state.request={signature,key:crypto.randomUUID()};const key=state.request.key;render();
    try{const result=await call('generate',{...draft,seed:Number(draft.seed),request_key:key});state.request=null;state.selectedJob=result.asset_id;if(scene===state.scene){state.drafts.set(scene,{...draft,seed:String((Number(draft.seed)+1)%4294967296)});await refresh();}}
    catch(error){state.error=error.message;}
    finally{state.busy=false;if(active())render();}
  });
  app.addEventListener('click',async e=>{
    const button=e.target.closest('[data-ai]');if(!button)return;
    if(button.dataset.ai==='select-job'){capture();state.selectedJob=Number(button.dataset.id);repaint();app.querySelector(`[data-ai="select-job"][data-id="${state.selectedJob}"]`)?.focus();}
    if(button.dataset.ai==='refresh'){capture();state.imagesLoaded=false;state.performanceLoaded=false;await refresh();}
    if(button.dataset.ai==='performance-more'&&!state.busy){
      capture();capturePerformance();state.busy=true;
      try{await loadPerformanceAssets(state.performanceNext);}catch(error){state.error=error.message;}
      finally{state.busy=false;if(active())repaint();}
    }
    if(button.dataset.ai==='images-more'&&!state.busy){capture();state.busy=true;try{await loadImages(state.imageNext);}catch(error){state.error=error.message;}finally{state.busy=false;if(active())repaint();}}
    if(button.dataset.ai==='use'&&!state.busy){state.busy=true;button.disabled=true;
      try{await A.studioAssetsReload();LightekStudioTimeline.insert(Number(button.dataset.id));LightekStudioProduction.go('edit',undefined,true);toast('Generated media added to the edit. Save changes to keep the placement.');}
      catch(error){state.error=error.message;toast(error.message);}finally{state.busy=false;}
    }
  });
  window.addEventListener('hashchange',()=>{if(!active()){capture();clearTimeout(state.timer);}});
  function repaint(){
    const focused=app.querySelector(':focus'),name=focused?.name;
    const scope=focused?.closest('[data-ai-performance]')?'[data-ai-performance]':focused?.closest('[data-ai-setup]')?'[data-ai-setup]':'[data-ai-form]';
    const details=app.querySelector('[data-ai-form] details'),open=details?.open;
    const start=focused?.selectionStart,end=focused?.selectionEnd;
    const player=app.querySelector('.ai-monitor video,.ai-monitor audio');
    render();
    const nextDetails=app.querySelector('[data-ai-form] details');
    if(nextDetails&&open!==undefined)nextDetails.open=open;
    const replacement=app.querySelector('.ai-monitor video,.ai-monitor audio');
    if(player&&replacement&&player.getAttribute('src')===replacement.getAttribute('src'))replacement.replaceWith(player);
    if(name){const target=app.querySelector(`${scope} [name="${CSS.escape(name)}"]`);target?.focus({preventScroll:true});if(typeof start==='number'&&target?.setSelectionRange)try{target.setSelectionRange(start,end);}catch(_){}}
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
