const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');const {JSDOM}=require('jsdom');
async function check(dashboard,restore=false,variant='bench'){
 const dom=new JSDOM(dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create"></div>':'<div id="app"></div>',{url:'https://studio.example/#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let submitted,attempt=restore?1:0,retried=0,quoted;
 const actingGrasp=variant==='grasp_acting',carrying=variant==='carry',grasping=variant==='grasp'||actingGrasp,focusing=variant==='attention',target=grasping?'ball':carrying?'parcel':'seat';
 const inputs={name:'Sentinel',dialogue:'We can build this world together.',voice:'en-us',colors:{skin:'#925e43',wardrobe:'#344e78',hair:'#211916'},emotion:'friendly',body_action:'still',entrance:'none',gesture:'still',scene_template:actingGrasp?'grasp_acting':'bench',camera_mode:'character',mechanics:{action:grasping?'grasp':carrying?'carry':'bench',version:actingGrasp?3:(focusing||grasping)?2:1,target_id:target},...(focusing?{attention:{kind:'camera',start:3.25,end:6.4}}:{})};
 window.nevaeh={execute:async({capability,payload})=>{let result;switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
  case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
  case 'assets.list':result={assets:[{id:61,name:'Legacy performer',kind:'blend',status:'ready',metadata:{character_profile:{bindings:{jaw_open:{}},motions:[]}}}]};break;
  case 'ai.jobs':result=[];break;case 'operations.list':result={operations:[],publications:[]};break;case 'workflow.status':result={ready:true,assets:[]};break;
  case 'ai.status':throw Error('Mechanics must not query Genesis');
  case 'character.scene.catalog':result={scene_templates:[{key:inputs.scene_template,name:'Walk, sit and stand',available:true,contact_targets:[{id:target,name:'Scene prop'}],mechanics_targets:[{id:target,name:'Scene prop',action:inputs.mechanics.action,version:inputs.mechanics.version}],defaults:{...inputs,...inputs.colors}},{key:'studio',name:'Plain stage',available:true,defaults:{...inputs,mechanics:null}}],production_templates:[],saved_templates:[],default_scene_template:actingGrasp?'grasp_acting':'bench'};break;
  case 'character.scene.prepare':submitted=payload;attempt=1;result={operation_id:80,status:'pending',phase:'queued'};break;
  case 'character.scene.status':result=!attempt?{status:'idle'}:attempt===1?{operation_id:80,inputs,status:'failed',phase:'rendering_preview',error:'Interrupted'}:{operation_id:80,inputs,status:'completed',phase:'ready',scene_id:9,url:'/mechanics-proof.mp4'};break;
  case 'character.scene.retry':retried++;attempt=2;result={operation_id:80,status:'pending',phase:'queued'};break;
  case 'character.scene.quote':quoted=payload;result={operation_id:82,status:'awaiting_payment',quote:{total_cents:550,currency:'USD'}};break;
  default:throw Error(capability);
 }return {result};}};
 if(dashboard){window.fetch=async(url,options)=>({status:'completed',result:(await window.nevaeh.execute(JSON.parse(options.body))).result});window.nevaeh.parseResponse=async response=>response;}
 const button=text=>[...window.document.querySelectorAll('button')].find(el=>el.textContent===text);
 const field=text=>[...window.document.querySelectorAll('label')].find(el=>el.textContent.startsWith(text))?.querySelector('select,input,textarea');
 const set=(element,value)=>{Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element),'value').set.call(element,value);element.dispatchEvent(new window.Event('change',{bubbles:true}));};
 async function until(check){for(let i=0;i<400;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error(window.document.body.textContent);}
 try{
  window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));if(!dashboard)window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
  await until(()=>button('Performed ShortCharacter · voice · cuts'));button('Performed ShortCharacter · voice · cuts').click();
  await until(()=>field('Coordinated action')?.value===target);
  if(grasping){assert(window.document.body.textContent.includes(actingGrasp?'gaze lock':'Fingers and thumb bend'));assert(field('Coordinated action').textContent.includes('Close fingers'));}if(actingGrasp){assert(field('attention target').closest('fieldset').disabled);assert(window.document.body.textContent.includes('Acting beats own the gaze'));}
  assert(field('body action').disabled);assert(field('entrance').disabled);assert(field('Starter action').disabled);assert.equal(field('Starter action').value,'still');
  if(!restore){
   set(field('Reusable performer'),'61');await until(()=>button('Prepare performed short').disabled);assert(window.document.body.textContent.includes('version 1 mechanics bindings'));
   set(field('Reusable performer'),'');await until(()=>!button('Prepare performed short').disabled);
   set(field('Coordinated action'),'');await until(()=>!field('body action').disabled);
   set(field('Coordinated action'),target);await until(()=>field('body action').disabled);
   if(focusing){assert.equal(field('attention target').value,'camera');set(field('attention target'),'object:'+target);set(field('attention target'),'camera');}
   button('Prepare performed short').click();await until(()=>submitted);assert.deepEqual(JSON.parse(JSON.stringify(submitted.mechanics)),inputs.mechanics);assert.equal(submitted.body_action,'still');assert.equal(submitted.entrance,'none');assert.equal(submitted.gesture,'still');if(focusing)assert.deepEqual(JSON.parse(JSON.stringify(submitted.attention)),inputs.attention);
  }
  if(focusing){assert.equal(field('attention target').value,'camera');assert.equal(field('start looking').value,'3.25');}
  await until(()=>button('Retry character preparation'));button('Retry character preparation').click();
  await until(()=>window.document.querySelector('video[src="/mechanics-proof.mp4"]'));assert.equal(retried,1);
  button('Get performed shot export price').click();await until(()=>quoted);assert.equal(quoted.operation_id,80);
  console.log(`${dashboard?'Dashboard':'PWA'}: ${variant} ${restore?'restoration':'typed submission'}, legacy guards, retry, preview and existing quote passed`);
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
module.exports={check};
if(require.main===module)(async()=>{await check(false);await check(true);await check(false,true);await check(true,true);})().catch(error=>{console.error(error);process.exitCode=1;});
