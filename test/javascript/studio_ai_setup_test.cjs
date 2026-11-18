const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {JSDOM}=require('jsdom');
(async()=>{
  const dom=new JSDOM('<!doctype html><main id="lightek-studio-dashboard"><div id="app"></div></main>',{url:'https://studio.test/#/studio/7/ai',runScripts:'outside-only'});
  dom.window.structuredClone=structuredClone;dom.window.CSS={escape:s=>s};
  const context=dom.getInternalVMContext(),evaluate=source=>vm.runInContext(source,context),document=dom.window.document;
  evaluate(`
    const app=document.getElementById('app'),requests=[],record={scene:{id:7},project:{id:4}};
    const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const studioCurrentSceneId=()=>7,toast=v=>window.lastToast=v;
    let mode='workflows',ready=false,phase='queued',operator=true;
    window.LightekStudioProduction={mode:()=>mode,go:(target,id)=>{mode=target;window.lastRoute={target,id}}};
    window.LightekStudioTimeline={insert:id=>window.inserted=id};
    const A={studioAssetsReload:async()=>{}};
    const nevaeh={execute:async request=>{
      requests.push(structuredClone(request));let result;
      switch(request.capability){
        case 'studio.workspace.ai.setup.status': result={can_manage:operator,install:phase==='queued'?{}:{status:phase,phase:'downloading_model',model:'real.safetensors',downloaded_bytes:1073741824,total_bytes:4294967296},workers:[{id:12,domain:'worker.example.test'}],packages:[{id:'concept',name:'Concept images',devices:['cpu','cuda'],ram_gib:8,free_disk_gib:24,vram_mib:4096},{id:'video',name:'Video shots',devices:['cuda'],ram_gib:32,free_disk_gib:80,vram_mib:24576}]};break;
        case 'studio.workspace.ai.setup.install': phase='running';result={status:'queued'};break;
        case 'studio.workspace.ai.status':result={connected:ready,recipes:ready?[{id:'image',name:'Concept image',kind:'image',steps:20,ready:true}]:[],models:ready?['real.safetensors']:[],performances:ready?[{id:'musetalk',name:'MuseTalk',action:'Lip sync',source:['image','video'],driver:'audio',configured:true},{id:'liveportrait',name:'LivePortrait',action:'Animate a portrait',source:['image'],driver:'video',configured:true},{id:'facefusion',name:'FaceFusion',action:'Change an actor',source:['image'],driver:'video',configured:false}]:[]};break;
        case 'studio.workspace.ai.jobs':result=ready?[{asset_id:88,status:'ready',kind:'image',name:'Finished shot',prompt:'A real shot',seed:42,preview_url:'/result.png'}]:[];break;
        case 'studio.workspace.ai.generate':result={asset_id:99};break;
        case 'studio.workspace.assets.list':result={assets:[{id:2,kind:'image',name:'Portrait'},{id:3,kind:'audio',name:'Dialogue'},{id:4,kind:'video',name:'Driver'}]};break;
        default:throw Error(request.capability);
      }
      return {result};
    }};
    function render(){app.innerHTML=LightekStudioAI.view(record,mode)}
  `);
  vm.runInContext(fs.readFileSync('public/lightek/studio-ai.js','utf8'),context);
  const settle=async()=>{for(let i=0;i<12;i++)await new Promise(r=>setImmediate(r));};
  evaluate('render()');await settle();
  assert(document.querySelector('[data-ai-setup]'));
  assert.match(document.querySelector('[data-ai-setup]').textContent,/24 GB free disk/);
  const prompt=document.querySelector('[name=prompt]');prompt.value='Keep this original shot';prompt.dispatchEvent(new dom.window.Event('input',{bubbles:true}));
  const form=document.querySelector('[data-ai-setup]');form.querySelector('[name=package_id]').value='video';form.querySelector('[name=device]').value='cuda';
  form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();
  const install=JSON.parse(evaluate('JSON.stringify(requests.find(r=>r.capability.endsWith("setup.install")))'));
  assert.equal(install.payload.installation_id,'12');assert.equal(install.payload.package_id,'video');assert.equal(install.payload.device,'cuda');assert.equal(install.payload.scene_id,7);
  assert.equal(document.querySelector('[name=prompt]').value,'Keep this original shot');
  assert.equal(document.querySelector('progress').value,1073741824);assert.equal(document.querySelector('progress').max,4294967296);
  assert(document.querySelector('[data-ai-setup] button').disabled);
  evaluate("phase='ready';ready=true");document.querySelector('[data-ai="refresh"]').click();await settle();
  assert(!document.querySelector('[data-ai-form] button').disabled);
  const performance=document.querySelector('[data-ai-performance]');
  performance.elements.input_asset_id.value='2';performance.elements.driver_asset_id.value='3';
  assert.equal(performance.elements.recipe.querySelector('option[value=facefusion]'),null);
  performance.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();
  const sent=JSON.parse(evaluate('JSON.stringify(requests.find(r=>r.capability.endsWith("ai.generate")))')).payload;
  assert.equal(sent.recipe,'musetalk');assert.equal(sent.input_asset_id,'2');assert.equal(sent.driver_asset_id,'3');
  // A sample's successful ingest uses the existing edit handoff.
  document.querySelector('[data-ai="use"]').click();await settle();assert.equal(dom.window.inserted,88);assert.equal(dom.window.lastRoute.target,'edit');
  evaluate("mode='ai'");dom.window.LightekStudioAI.startShot(7,{id:'shot-1',name:'Close up',prompt:'An expressive original character'});evaluate('render()');
  assert.equal(document.querySelector('[name=shot_id]').value,'shot-1');assert.equal(document.querySelector('[name=prompt]').value,'An expressive original character');
  // Refresh keeps the typing caret and recipe/worker selections.
  const edited=document.querySelector('[name=prompt]');edited.focus();edited.setSelectionRange(3,7);
  document.querySelector('[data-ai="refresh"]').click();await settle();
  assert.equal(document.activeElement.name,'prompt');assert.equal(document.activeElement.selectionStart,3);assert.equal(document.activeElement.selectionEnd,7);
  evaluate("operator=false;mode='workflows'");document.querySelector('[data-ai=refresh]').click();await settle();assert.equal(document.querySelector('[data-ai-setup]'),null,'customers never receive installer controls');assert.match(document.querySelector('.ai-worker').textContent,/managed by Lightek/);
  dom.window.close();console.log('Genesis worker setup DOM checks passed');
})().catch(error=>{console.error(error);process.exit(1)});
