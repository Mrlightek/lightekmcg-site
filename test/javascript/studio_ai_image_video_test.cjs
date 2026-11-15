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
    let mode='ai',ready=true,phase='ready';
    window.LightekStudioProduction={mode:()=>mode,go:(target,id)=>{mode=target;window.lastRoute={target,id}}};
    window.LightekStudioTimeline={insert:id=>window.inserted=id};
    const A={studioAssetsReload:async()=>{}};
    const nevaeh={execute:async request=>{
      requests.push(structuredClone(request));let result;
      switch(request.capability){
        case 'studio.workspace.ai.setup.status': result={install:phase==='queued'?{}:{status:phase,phase:'downloading_model',model:'real.safetensors',downloaded_bytes:1073741824,total_bytes:4294967296},workers:[{id:12,domain:'worker.example.test'}],packages:[{id:'concept',name:'Concept images',devices:['cpu','cuda'],ram_gib:8,free_disk_gib:24,vram_mib:4096},{id:'video',name:'Video shots',devices:['cuda'],ram_gib:32,free_disk_gib:80,vram_mib:24576}]};break;
        case 'studio.workspace.ai.setup.install': phase='running';result={status:'queued'};break;
        case 'studio.workspace.ai.status':result={connected:ready,recipes:ready?[{id:'image',name:'Concept image',kind:'image',ready:true},{id:'wan22_image_video',name:'Animate image',kind:'video',input_kind:'image',ready:true}]:[],models:ready?['real.safetensors']:[]};break;
        case 'studio.workspace.ai.jobs':result=ready?[{asset_id:88,status:'ready',kind:'image',name:'Finished shot',prompt:'A real shot',seed:42,preview_url:'/result.png'}]:[];break;
        case 'studio.workspace.ai.generate':result={asset_id:99};break;
        case 'studio.workspace.assets.list':result={assets:[{id:request.payload.before?10:11,name:'Starting still',kind:'image',status:'ready',proxy_url:'/start.png'}],next_before:request.payload.before?null:11};break;
        default:throw Error(request.capability);
      }
      return {result};
    }};
    function render(){app.innerHTML=LightekStudioAI.view(record)}
  `);
  vm.runInContext(fs.readFileSync('public/lightek/studio-ai.js','utf8'),context);
  const settle=async()=>{for(let i=0;i<12;i++)await new Promise(r=>setImmediate(r));};
  evaluate('render()');await settle();
  const change=async(selector,value)=>{const el=document.querySelector(selector);assert(el,selector);el.value=value;el.dispatchEvent(new dom.window.Event('change',{bubbles:true}));await settle();};
  await change('[name=recipe]','wan22_image_video');assert(document.querySelector('[name=input_asset_id]').required);await change('[name=input_asset_id]','11');assert.equal(document.querySelector('img[alt="Starting image"]').getAttribute('src'),'/start.png');
  await change('[name=prompt]','Animate this scene');document.querySelector('[data-ai=images-more]').click();await settle();assert.equal(document.querySelector('[name=input_asset_id]').value,'11');assert(document.querySelector('[name=input_asset_id] option[value="10"]'));
  const listed=Number(evaluate('requests.filter(r=>r.capability==="studio.workspace.assets.list").length'));document.querySelector('[data-ai=refresh]').click();await settle();assert(Number(evaluate('requests.filter(r=>r.capability==="studio.workspace.assets.list").length'))>listed);assert.equal(document.querySelector('[name=input_asset_id]').value,'11');
  const form=document.querySelector('[data-ai-form]');form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();
  const sent=JSON.parse(evaluate('JSON.stringify(requests.find(r=>r.capability.endsWith("ai.generate")))'));assert.equal(sent.payload.input_asset_id,'11');assert.equal(sent.payload.recipe,'wan22_image_video');assert.equal(sent.payload.prompt,'Animate this scene');assert.equal(sent.payload.scene_id,7);assert(!Object.hasOwn(sent.payload,'image_url'));
  await change('[name=recipe]','image');assert.equal(document.querySelector('[name=input_asset_id]'),null);document.querySelector('[data-ai-form]').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();const textOnly=JSON.parse(evaluate('JSON.stringify(requests.filter(r=>r.capability.endsWith("ai.generate")).at(-1))'));assert(!Object.hasOwn(textOnly.payload,'input_asset_id'));
  dom.window.close();console.log('STUDIO_AI_IMAGE_VIDEO_DOM_PASS workflow-specific image selection/preview, pagination/draft retention, source-bound submission and text-only separation');
})().catch(error=>{console.error(error);process.exit(1)});
