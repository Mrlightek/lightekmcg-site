const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {JSDOM}=require('jsdom');
async function check(dashboard){
 const dom=new JSDOM(dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create"></div>':'<div id="app"></div>',{url:'https://studio.example/#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let launched=false,preparations=[],launches=[],genesis=0;
 const base={id:3,name:'Workspace',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]};
 const defaults={name:'Sentinel',dialogue:'We protect this city.',gesture:'wave_right',camera_mode:'character'};
 window.nevaeh={execute:async({capability,payload})=>{
  let result;switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
   case 'bootstrap':result={projects:[base,...(launched?[{id:4,name:'Original pilot',unassigned_scenes:[{id:9,name:'Opening scene',settings:{},lock_version:1}]}]:[])]};break;
   case 'assets.list':result={assets:[]};break;
   case 'ai.jobs':result=[];break;
   case 'operations.list':result={operations:[],publications:[]};break;
   case 'workflow.status':result={ready:true,assets:[]};break;
   case 'ai.status':genesis++;throw Error('Template flow must not depend on Genesis');
   case 'character.scene.catalog':result={scene_templates:[{key:'studio',name:'Plain stage',available:true,defaults},{key:'current',name:'Current scene set',available:true,defaults},{key:'library:tpl_night_exterior',name:'Atlanta Night Exterior',available:true,defaults}],production_templates:[{key:'production/network_procedural_42',name:'Network Procedural',scene_count:3}],saved_templates:[{id:5,name:'My saved show',scene_count:2}],default_scene_template:payload.scene_id===9?'current':'studio'};break;
   case 'character.scene.prepare':preparations.push(payload);result={operation_id:80+preparations.length,status:'pending',phase:'queued'};break;
   case 'character.scene.status':result=payload.operation_id?{operation_id:payload.operation_id,status:'completed',phase:'ready',scene_id:8,url:'/template-proof.mp4'}:{status:'idle'};break;
   case 'character.template.use':launches.push(payload);launched=true;result={project_id:4,name:payload.name,scenes:[{id:9,name:'Opening scene'}],status:'staged'};break;
   default:throw Error(capability);
  }return {result};
 }};
 if(dashboard){window.fetch=async(url,options)=>({status:'completed',result:(await window.nevaeh.execute(JSON.parse(options.body))).result});window.nevaeh.parseResponse=async response=>response;}
 const button=label=>[...window.document.querySelectorAll('button')].find(el=>el.textContent===label);
 const field=label=>[...window.document.querySelectorAll('label')].find(el=>el.textContent.startsWith(label))?.querySelector('select,input,textarea');
 const set=(element,value)=>{Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element),'value').set.call(element,value);element.dispatchEvent(new window.Event(element.tagName==='SELECT'?'change':'input',{bubbles:true}));};
 async function until(check){for(let i=0;i<400;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error(window.document.body.textContent);}
 try{
  window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));
  if(!dashboard)window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
  await until(()=>button('Performed ShortCharacter · voice · cuts'));button('Performed ShortCharacter · voice · cuts').click();
  await until(()=>field('Scene setup')&&!field('Scene setup').disabled);
  set(field('Scene setup'),'library:tpl_night_exterior');set(field('Camera coverage'),'template');set(field('Starter action'),'nod');
  button('Prepare performed short').click();await until(()=>window.document.querySelector('video[src="/template-proof.mp4"]'));
  assert.equal(preparations[0].scene_template,'library:tpl_night_exterior');assert.equal(preparations[0].camera_mode,'template');assert.equal(preparations[0].gesture,'nod');
  set(field('Production or show template'),'production:production/network_procedural_42');set(field('New production name'),'Original pilot');
  button('Create template production').click();await until(()=>button('Open Opening scene'));
  assert.equal(launches[0].source,'production');assert.equal(launches[0].template_key,'production/network_procedural_42');assert.equal(launches[0].scene_id,7);
  button('Open Opening scene').click();await until(()=>field('Scene setup')?.value==='current');
  assert(window.location.hash.includes('/9/performed'));
  await until(()=>button('Prepare performed short')&&!button('Prepare performed short').disabled);
  button('Prepare performed short').click();await until(()=>preparations.length===2);
  assert.equal(preparations[1].scene_id,9);assert.equal(preparations[1].scene_template,'current');
  await until(()=>window.document.querySelector('video[src="/template-proof.mp4"]'));
  set(field('Production or show template'),'saved:5');button('Create template production').click();await until(()=>launches.length===2);
  assert.equal(launches[1].source,'saved');assert.equal(launches[1].project_id,5);assert.equal(launches[1].scene_id,9);assert.equal(genesis,0);
  console.log((dashboard?'Dashboard':'PWA')+': scene setup, production launch, scene opening and saved-show launch passed');
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
(async()=>{await check(false);await check(true);})().catch(error=>{console.error(error);process.exitCode=1;});
