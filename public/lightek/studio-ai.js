/* Generative media stays in the production: prompt → local worker → saved asset → edit. */
(() => {
  if(!document.querySelector('#lightek-studio-dashboard'))return;
  const state={request:null,scene:0,loaded:false,loading:false,busy:false,status:null,jobs:[],error:'',timer:null,drafts:new Map()};
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.ai.'+action,payload:{scene_id:studioCurrentSceneId(),...payload}})).result;
  const active=()=>window.LightekStudioProduction?.mode()==='ai';
  function capture(){const form=app.querySelector('[data-ai-form]');if(form)state.drafts.set(state.scene,Object.fromEntries(new FormData(form)));}
  async function refresh(){
    if(state.loading)return;state.loading=true;const scene=state.scene;
    try{
      const [status,jobs]=await Promise.all([call('status'),call('jobs')]);
      if(scene!==state.scene)return;state.status=status;state.jobs=jobs;state.error='';state.loaded=true;
    }catch(error){if(scene===state.scene){state.error=error.message;state.loaded=true;}}
    finally{state.loading=false;if(active()){if(scene===state.scene){capture();render();}else queueMicrotask(refresh);}}
    clearTimeout(state.timer);if(active()&&state.jobs.some(j=>['uploaded','processing'].includes(j.status)))state.timer=setTimeout(refresh,5000);
  }
  function view(record){
    if(state.scene!==record.scene.id){capture();state.scene=record.scene.id;state.loaded=false;state.status=null;state.jobs=[];state.error='';clearTimeout(state.timer);}
    if(!state.loaded&&!state.loading)refresh();
    const draft=state.drafts.get(state.scene)||{},status=state.status,ready=(status?.recipes||[]).filter(r=>r.ready),recipe=ready.find(r=>r.id===draft.recipe)||ready[0];
    return `<section class="studio-ai production-panel" aria-label="AI Studio"><header><span class="eb">LIGHTEK / AI STUDIO</span><h2>Imagine it. Make it here.</h2><p>Generate concept art and media with your own installed models. Saved results stay in this production’s asset library.</p></header><div class="ai-layout"><div><form data-ai-form><label class="fld"><span>What are we creating?</span><select name="recipe" ${ready.length?'':'disabled'}>${ready.map(r=>`<option value="${E(r.id)}" ${r.id===recipe?.id?'selected':''}>${E(r.name)} · ${E(r.kind)}</option>`).join('')||'<option>No ready generation workflows</option>'}</select></label><label class="fld"><span>Describe the shot</span><textarea name="prompt" maxlength="2000" required placeholder="An expressive character in a warmly lit recording studio, cinematic composition…">${E(draft.prompt||'')}</textarea></label><details><summary>Refine the generation</summary><label class="fld"><span>Avoid in the result</span><textarea name="negative" maxlength="2000">${E(draft.negative||'')}</textarea></label><label class="fld"><span>Installed local model</span><select name="model">${(status?.models||[]).map(m=>`<option ${m===draft.model?'selected':''}>${E(m)}</option>`).join('')||'<option value="">Workflow-managed model</option>'}</select></label><label class="fld"><span>Seed · keep it to repeat a variation</span><input type="number" name="seed" min="0" max="4294967295" step="1" value="${E(draft.seed||Math.floor(Math.random()*4294967296))}"></label></details><button class="vw-btn" ${state.busy||!ready.length?'disabled':''}>${state.busy?'Submitting…':'Generate on my worker'}</button><p role="status">${state.error?E(state.error):state.loading?'Checking your worker…':status?.connected?ready.length?'Local engine connected. No hosted generation API is used.':'Engine connected; its installed nodes or models are not ready for these workflows.':E(status?.reason||'Checking your worker…')}</p><button class="vw-btn" type="button" data-ai="refresh">Check worker & jobs</button></form><aside class="ai-animation"><h3>Character animation</h3><p>Reusable Blender characters, dialogue takes and saved performances belong to the same production. Generated artwork is concept art; it is not automatically a rigged performer.</p><a class="vw-btn" href="#/studio/${record.scene.id}/cast" data-production-mode="cast">Open character direction</a><a class="vw-btn" href="#/studio/${record.scene.id}/stage" data-production-mode="stage">Stage the shot</a><p>The current toon rig and volume-driven mouth controls are basic. Production character creation, phoneme lip sync and motion generation still need implementation.</p></aside></div><section class="ai-results"><h3>Generation jobs & results</h3>${state.jobs.map(j=>`<article class="ai-result"><header><strong>${E(j.name)}</strong><span>${E(j.status==='uploaded'?'Queued':j.status==='processing'?j.phase:j.status)}</span></header>${j.preview_url?(j.kind==='image'?`<img alt="${E(j.name)}" src="${E(j.preview_url)}">`:['video','audio'].includes(j.kind)?`<${j.kind} controls src="${E(j.preview_url)}"></${j.kind}>`:''):''}<p>${E(j.prompt||'')}</p><small>Seed ${j.seed??'—'}</small>${j.error?`<p role="alert">${E(j.error)}</p>`:''}${j.status==='ready'&&['image','video','audio'].includes(j.kind)?`<button class="vw-btn" data-ai="use" data-id="${j.asset_id}" ${state.busy?'disabled':''}>Add result to edit</button>`:''}</article>`).join('')||'<p>No generations in this production yet. Submit a prompt once a local workflow is ready.</p>'}</section></div></section>`;
  }
  app.addEventListener('input',e=>{if(e.target.closest('[data-ai-form]'))capture();});
  app.addEventListener('change',e=>{if(e.target.closest('[data-ai-form]'))capture();});
  app.addEventListener('submit',async e=>{
    const form=e.target.closest('[data-ai-form]');if(!form)return;e.preventDefault();if(state.busy)return;capture();const scene=state.scene,draft=state.drafts.get(scene);
    state.busy=true;state.error='';const signature=JSON.stringify([scene,draft]);if(state.request?.signature!==signature)state.request={signature,key:crypto.randomUUID()};const key=state.request.key;render();
    try{await call('generate',{...draft,seed:Number(draft.seed),request_key:key});state.request=null;if(scene===state.scene){state.drafts.set(scene,{...draft,seed:String((Number(draft.seed)+1)%4294967296)});await refresh();}}
    catch(error){state.error=error.message;}
    finally{state.busy=false;if(active())render();}
  });
  app.addEventListener('click',async e=>{
    const button=e.target.closest('[data-ai]');if(!button)return;
    if(button.dataset.ai==='refresh'){capture();await refresh();}
    if(button.dataset.ai==='use'&&!state.busy){state.busy=true;button.disabled=true;
      try{await A.studioAssetsReload();LightekStudioTimeline.insert(Number(button.dataset.id));LightekStudioProduction.go('edit',undefined,true);toast('Generated media added to the edit. Save changes to keep the placement.');}
      catch(error){state.error=error.message;toast(error.message);}finally{state.busy=false;}
    }
  });
  window.addEventListener('hashchange',()=>{if(!active()){capture();clearTimeout(state.timer);}});
  window.LightekStudioAI={view,busy:()=>state.busy};
})();
