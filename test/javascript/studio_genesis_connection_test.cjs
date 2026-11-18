const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const dom=new JSDOM('<div id="app"></div>',{
  url:'https://studio.example/lightek/index.html#/studio/7/create',
  runScripts:'outside-only',pretendToBeVisual:true
});
const {window}=dom;
let healthy=false,submitted;
const reason='The configured ComfyUI connection was refused. Check that ComfyUI is running.';
window.nevaeh={execute:async({capability,payload})=>{
  let result;
  switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
    case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
    case 'assets.list':result={assets:[]};break;
    case 'ai.jobs':result=[];break;
    case 'operations.list':result={operations:[],publications:[]};break;
    case 'ai.status':result=healthy?
      {connected:true,device:{type:'cuda'},models:[],genesis_workers:[{id:'local',label:'Local Genesis worker',video:true}],recipes:[{id:'wan22_video',ready:true,steps:20}],render_pools:[],performances:[]}:
      {connected:false,reason,reason_code:'engine_connection_refused',recipes:[],genesis_workers:[],render_pools:[],performances:[]};break;
    case 'ai.generate':submitted=payload;result={asset_id:23,status:'uploaded'};break;
    default:throw Error(capability);
  }
  return {result};
}};
const sleep=()=>new Promise(resolve=>setTimeout(resolve,10));
async function until(check){for(let i=0;i<150;i++){if(check())return;await sleep();}throw Error('UI did not reach expected state');}
function button(label){return [...window.document.querySelectorAll('button')].find(el=>el.textContent===label);}
(async()=>{
  try{
    window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));
    window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
    await until(()=>button('5s AI VideoWan 2.2'));
    button('5s AI VideoWan 2.2').click();
    await until(()=>button('Generate'));
    await until(()=>window.document.body.textContent.includes(reason));
    assert(button('Generate').disabled);
    assert(window.document.body.textContent.includes('engine_connection_refused'));
    const input=window.document.querySelector('textarea');
    Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set.call(input,'A sunny beach');
    input.dispatchEvent(new window.Event('input',{bubbles:true}));
    healthy=true;
    button('Recheck ComfyUI connection').click();
    await until(()=>!button('Generate').disabled);
    assert.equal(input.value,'A sunny beach','Rechecking must retain the prompt');
    button('Generate').click();
    await until(()=>submitted);
    assert.equal(submitted.prompt,'A sunny beach');
    assert.equal(submitted.recipe,'wan22_video');
    assert.equal(submitted.genesis_worker_id,'local');
    console.log('Studio Genesis connection: specific failure, disabled submission, retry and retained prompt passed');
  }finally{window.LightekUnifiedStudio?.leave();window.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
