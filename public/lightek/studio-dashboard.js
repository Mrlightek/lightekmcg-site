/* Native Dashboard host for shared Studio engines. No PWA document or iframe. */
var app=document.querySelector('#studio-root');
var E=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
var ST={loaded:false,loading:false,projects:[],workspaceMode:'3d',selectedObjectId:null,busy:false};
var STUDIO_WAVE2_STATE={storyboard:[],beats:[],checks:[],muted:[],scriptDraft:''},STUDIO_V3_STATE={},STUDIO_W4_STATE={},STUDIO_W5_STATE={presets:[]},STUDIO_WORKSPACE_LAYOUT={},STUDIO_WAVE2_TASKS=[];
var STUDIO_WORKSPACE_MODES=[{key:'3d',label:'Layout'},{key:'visual',label:'Camera'},{key:'script',label:'Script'},{key:'publish',label:'Deliver'}];
var AF={studio:()=>{}},A={},R={};
var studioCurrentSceneId=()=>Number(location.hash.match(/^#\/studio\/(\d+)/)?.[1]||0);
var studioSceneRecords=()=>ST.projects.flatMap(project=>{const rows=(project.productions||[]).flatMap(production=>(production.scenes||[]).map(scene=>({project,production,scene})));return[...rows,...(project.unassigned_scenes||project.scenes?.filter(scene=>!scene.production_id)||[]).map(scene=>({project,production:null,scene}))];});
var studioSceneRecord=id=>studioSceneRecords().find(r=>Number(r.scene.id)===Number(id));
var studioWorkspaceSelectedObject=scene=>scene?.objects.find(o=>Number(o.id)===Number(ST.selectedObjectId))||null;
var meProfile=()=>({id:Number(document.querySelector('#lightek-studio-dashboard').dataset.userId)}),me=meProfile;
var toast=message=>{let el=document.querySelector('[data-dashboard-studio-notice]');if(!el){el=document.createElement('div');el.dataset.dashboardStudioNotice='';el.role='status';el.className='studio-dashboard-notice';app.before(el);}el.textContent=message;};
var studioExecuteMutation=async(capability,payload)=>{const result=await nevaeh.execute({capability,payload});await A.studioLoad(true);return result.result;};
var render=()=>{
  if(!ST.loaded){app.innerHTML=`<section class="studio-dashboard-empty"><h1>Lightek Studio</h1><p role="status">${E(ST.error||'Opening your productions…')}</p>${ST.error?'<button class="vw-btn" data-a="studioReload">Try again</button>':''}</section>`;return;}
  const id=location.hash.split('/')[2];app.innerHTML=R.studio(id);app.classList.toggle('studio-dashboard-auxiliary',!app.querySelector('.visual-workbench,.studio-dashboard-advanced'));AF.studio?.(id);
  window.dispatchEvent(new CustomEvent('lightek:bootstrap'));
};
R.studio=id=>{
  const record=studioSceneRecord(Number(id));if(!record)return '<section class="studio-dashboard-empty"><h1>Choose a production</h1><a href="#/studio">Studio home</a></section>';
  LightekStudioApp.prepare(record);
  if(window.LightekStudioMusic?.active())return LightekStudioMusic.view(record);
  if(window.LightekStudioVisual?.enabled())return LightekStudioVisual.view(record);
  const modes=[['3d','Layout'],['visual','Camera'],['performance','Cast & performance'],['timeline','Edit & mix'],['script','Script'],['publish','Deliver']],mode=ST.workspaceMode;
  const panel=mode==='3d'?`<div class="studio-work-grid"><section>${LightekStudioApp.outliner?.(record.scene)||record.scene.objects.map(o=>`<button class="vw-btn" data-a="studioSelectObject" data-id="${o.id}">${E(o.name)}</button>`).join('')}</section><aside>${LightekStudioApp.inspector(record.scene)}</aside></div>${LightekStudioApp.tools(record)}`:mode==='visual'?LightekStudioApp.visual(record):mode==='publish'?LightekStudioApp.delivery(record,mode):LightekStudioApp.story(record,mode);
  return `<main class="studio-dashboard-advanced"><header><h1>${E(record.project.name)}</h1><nav>${modes.map(([key,label])=>`<button class="vw-btn" data-a="studioWorkspaceMode" data-mode="${key}">${label}</button>`).join('')}<a class="vw-btn" href="#/studio/${record.scene.id}/music">Music</a></nav></header>${panel||''}</main>`;
};
(() => {
  const root=document.querySelector('#lightek-studio-dashboard');if(!root)return;
  const site=root.dataset.siteId,endpoint='/dashboard/studio-broadcasting/execute?site_id='+encodeURIComponent(site);
  window.LightekStudioUploadUrl='/dashboard/studio-broadcasting/uploads?site_id='+encodeURIComponent(site);
  nevaeh.csrfToken=root.dataset.csrfToken;
  function surfaceUrls(value){if(typeof value==='string'&&/^\/api\/lightek\/pwa\/assets\/\d+\/(original|native|bundle|proxy|thumbnail)$/.test(value))return value.replace('/api/lightek/pwa/assets/','/dashboard/studio-broadcasting/assets/')+'?site_id='+encodeURIComponent(site);if(Array.isArray(value))return value.map(surfaceUrls);if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,surfaceUrls(v)]));return value;}
  nevaeh.execute=async request=>{const response=await fetch(endpoint,{method:'POST',credentials:'same-origin',headers:{...nevaeh.csrfHeaders(),'Content-Type':'application/json','Accept':'application/json'},body:JSON.stringify(request)});const data=await nevaeh.parseResponse(response);if(data.status!=='completed')throw Error(data.error||'Studio did not complete the operation.');return surfaceUrls(data);};
  A.studioLoad=async()=>{if(ST.loading)return;ST.loading=true;try{const data=await nevaeh.execute({capability:'studio.pwa.bootstrap',payload:{}});ST.projects=data.result.projects||[];ST.loaded=true;ST.error='';}catch(e){ST.error=e.message;toast(e.message);}finally{ST.loading=false;render();}};
  A.studioReload=()=>A.studioLoad();A.studioSelectObject=b=>window.LightekStudioViewportBridge.selectObject(Number(b.dataset.id));
  A.studioWorkspaceMode=b=>{ST.workspaceMode=b.dataset.mode;render();};
  window.LightekStudioViewportBridge={snapshot:()=>{const r=studioSceneRecord(studioCurrentSceneId());return r?{sceneId:r.scene.id,sceneName:r.scene.name,objects:JSON.parse(JSON.stringify(r.scene.objects)),selectedObjectId:ST.selectedObjectId,workspaceMode:ST.workspaceMode,busy:ST.busy,settings:r.scene.settings}:null;},selectObject:id=>{ST.selectedObjectId=id;render();},commitTransform:async(id,attributes)=>{const result=await nevaeh.execute({capability:'studio.scene_object.transform',payload:{scene_id:studioCurrentSceneId(),object_id:id,attributes}});const record=studioSceneRecord(studioCurrentSceneId()),o=record?.scene.objects.find(o=>o.id===id);if(o){if(result.result.object?.definition)o.definition=result.result.object.definition;else Object.assign(o.definition,attributes);if(result.result.object?.name)o.name=result.result.object.name;}if(result.result.lock_version!==undefined)record.scene.lock_version=result.result.lock_version;return result.result;}};
  app.addEventListener('click',e=>{const button=e.target.closest('[data-a]');if(button&&A[button.dataset.a]){e.preventDefault();Promise.resolve(A[button.dataset.a](button)).catch(error=>toast(error.message));}});
  window.addEventListener('hashchange',()=>{if(location.hash.startsWith('#/studio'))render();});
  document.addEventListener('turbo:before-cache',()=>{window.LightekMusicAudio?.stop();window.LightekStudioTimeline?.stop();});
  document.addEventListener('DOMContentLoaded',()=>{if(!location.hash.startsWith('#/studio'))history.replaceState(null,'',location.pathname+location.search+'#/studio'+(root.dataset.sceneId?'/'+root.dataset.sceneId+(root.dataset.workspace==='music'?'/music':''):''));A.studioLoad();},{once:true});
})();
