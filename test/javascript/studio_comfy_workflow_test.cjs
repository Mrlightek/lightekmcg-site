const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const dom=new JSDOM('<div id="app"></div>',{url:'https://studio.example/lightek/index.html#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
const {window}=dom;
let submitted;
window.nevaeh={execute:async({capability,payload})=>{
  let result;
  switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
    case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
    case 'assets.list':result={assets:[]};break;
    case 'ai.jobs':result=[];break;
    case 'ai.status':result={connected:true,device:{type:'cpu'},workflow:{ready:true},models:[],recipes:[],genesis_workers:[],render_pools:['standard'],performances:[]};break;
    case 'workflow.create':
      if(payload.prompt==='A dragon flies')throw Error('This workflow supports a cube, sphere or cylinder.');
      submitted=payload;result={operation_id:70,status:'pending'};break;
    case 'operations.list':result={operations:submitted?[{id:70,type:'build_scene',status:'completed',scene_id:7,draft_preview:true,artifacts:[{id:77,kind:'video',filename:'workflow-draft.mp4',url:'/workflow-proof.mp4'}]}]:[],publications:[]};break;
    default:throw Error(capability);
  }
  return {result};
}};
function button(label){return [...window.document.querySelectorAll('button')].find(el=>el.textContent===label);}
async function until(check){for(let i=0;i<150;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error('Expected Studio state did not appear');}
(async()=>{
  try{
    window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));
    window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
    await until(()=>button('ComfyUI CPU DraftBlender + MCP'));
    button('ComfyUI CPU DraftBlender + MCP').click();
    await until(()=>window.document.querySelector('[placeholder^="A cube spins"]'));
    assert(button('Render workflow draft').disabled);
    const field=window.document.querySelector('[placeholder^="A cube spins"]');
    Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set.call(field,'A dragon flies');
    field.dispatchEvent(new window.Event('input',{bubbles:true}));
    await until(()=>!button('Render workflow draft').disabled);
    button('Render workflow draft').click();
    await until(()=>window.document.querySelector('[role="alert"]')?.textContent.includes('supports a cube'));
    Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set.call(field,'A cube spins under soft lighting viewed from front');
    field.dispatchEvent(new window.Event('input',{bubbles:true}));
    await until(()=>!button('Render workflow draft').disabled);
    button('Render workflow draft').click();
    await until(()=>window.document.querySelector('video[src="/workflow-proof.mp4"]'));
    assert.equal(submitted.scene_id,7);
    assert.equal(submitted.prompt,field.value);
    assert.deepEqual(Object.keys(submitted).sort(),['prompt','request_key','scene_id']);
    assert(!window.document.body.textContent.includes('requires a CUDA worker'));
    console.log('Studio ComfyUI workflow: CPU-only submission and returned video preview passed');
  }finally{window.LightekUnifiedStudio?.leave();window.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
