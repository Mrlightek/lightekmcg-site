const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {JSDOM}=require('jsdom');
async function check(dashboard,acting=false){
 const dom=new JSDOM(dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create"></div>':'<div id="app"></div>',{url:'https://studio.example/#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let submitted,checked=0,quoted;
 window.nevaeh={execute:async({capability,payload})=>{
  let result;switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
   case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
   case 'assets.list':result={assets:[]};break;
   case 'ai.jobs':result=[];break;
   case 'operations.list':result={operations:[],publications:[]};break;
   case 'workflow.status':result={ready:true,assets:[]};break;
   case 'ai.status':throw Error('Performed Short must not query Genesis');
   case 'character.scene.catalog':result={scene_templates:[{key:'studio',name:'Plain stage',available:true,defaults:{name:'Sentinel',dialogue:'We protect this city.',gesture:'wave_right',camera_mode:'character'}}],production_templates:[],saved_templates:[],default_scene_template:'studio'};break;
   case 'character.scene.prepare':submitted=payload;result={operation_id:80,status:'pending',phase:'queued'};break;
   case 'character.scene.status':checked++;if(!submitted){result={status:'idle'};break;}result={operation_id:80,status:'completed',phase:'ready',scene_id:9,cast_asset_id:10,preview_operation_id:81,url:'/performed-proof.mp4'};break;
   case 'character.scene.quote':quoted=payload;result={operation_id:82,status:'awaiting_payment',quote:{total_cents:550,currency:'USD'}};break;
   default:throw Error(capability);
  }return {result};
 }};
 if(dashboard){window.fetch=async(url,options)=>({status:'completed',result:(await window.nevaeh.execute(JSON.parse(options.body))).result});window.nevaeh.parseResponse=async response=>response;}
 const field=label=>[...window.document.querySelectorAll('label')].find(el=>el.textContent.startsWith(label))?.querySelector('select,input,textarea');
 const set=(element,value)=>{Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element),'value').set.call(element,value);element.dispatchEvent(new window.Event('change',{bubbles:true}));};
 const button=label=>[...window.document.querySelectorAll('button')].find(el=>el.textContent===label);
 async function until(check){for(let i=0;i<400;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error(window.document.body.textContent);}
 try{
  window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));
  if(!dashboard)window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
  await until(()=>button('Performed ShortCharacter · voice · cuts'));button('Performed ShortCharacter · voice · cuts').click();
  await until(()=>button('Prepare performed short')&&!button('Prepare performed short').disabled);
  if(acting){set(field('facial cue'),'friendly');set(field('body action'),'point_right');set(field('entrance'),'from_left');await until(()=>field('Starter action').value==='still');}
  button('Prepare performed short').click();
  await until(()=>window.document.querySelector('video[src="/performed-proof.mp4"]'));
  assert.equal(submitted.scene_id,7);assert.equal(submitted.name,'Sentinel');assert.equal(submitted.dialogue,'We protect this city.');assert(checked);if(acting){assert.equal(submitted.emotion,'friendly');assert.equal(submitted.body_action,'point_right');assert.equal(submitted.entrance,'from_left');assert.equal(submitted.gesture,'still');}
  const link=[...window.document.querySelectorAll('a')].find(el=>el.textContent==='Open editable character scene');assert(link.href.includes('9'));
  button('Get performed shot export price').click();await until(()=>quoted);assert.equal(quoted.operation_id,80);
  await until(()=>button('Continue to export checkout'));
  console.log((dashboard?'Dashboard':'PWA')+': performed short submission, polling, video, edit and quote passed without Genesis');
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
(async()=>{await check(false);await check(true);await check(false,true);await check(true,true);})().catch(error=>{console.error(error);process.exitCode=1;});
