const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
async function check(surface){
 const dom=new JSDOM('<div id="app"></div>',{url:'https://studio.example/lightek/index.html#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let submitted,saved,genesisCalls=0;
 const graph={version:1,seed:42,canvas:{width:640,height:360,fps:24,duration:4},camera:{x:.08,y:0},nodes:[{id:'group',name:'Environment',children:[{id:'sky',name:'Night sky',template:'sky.night',x:.5,y:.5,width:1,height:1,z_index:0,depth:0,opacity:1,rotation:0,fit:'stretch'}],x:0,y:0,scale:1,rotation:0,z_index:0,depth:.2,opacity:1}]};
 window.nevaeh={execute:async({capability,payload})=>{
  let result;
  switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
   case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:saved?{composition_2d:saved}:{},lock_version:saved?2:1}]}]};break;
   case 'assets.list':result={assets:[]};break;
   case 'ai.jobs':result=[];break;
   case 'ai.status':genesisCalls++;throw Error('Genesis is offline');
   case 'workflow.status':result={ready:true,message:'2D compositor tools available.',assets:[{key:'sky.night',name:'Night sky',url:'/lightek/assets2d/sky-night.svg'}]};break;
   case 'workflow.plan':if(payload.prompt==='A dragon flies')throw Error('Use a supported scene prompt, such as: A nighttime park with a character sitting on a bench.');result={composition:JSON.parse(JSON.stringify(graph))};break;
   case 'workflow.save':assert.equal(payload.lock_version,1);saved=payload.composition;result={composition:saved,lock_version:2};break;
   case 'workflow.create':submitted=payload;result={operation_id:70,status:'pending'};break;
   case 'operations.list':result={operations:submitted?[{id:70,type:'edit_media',status:'completed',scene_id:7,draft_preview:true,layered_scene:true,artifacts:[{id:77,kind:'video',filename:'scene.mp4',url:'/workflow-proof.mp4'}]}]:[],publications:[]};break;
   default:throw Error(capability);
  }
  return {result};
 }};
 const button=label=>[...window.document.querySelectorAll('button')].find(el=>el.textContent===label);
 async function until(check){for(let i=0;i<200;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error('Expected Studio state did not appear: '+window.document.body.textContent.slice(-1500));}
 function field(label){const wrapper=[...window.document.querySelectorAll('label')].find(el=>el.textContent.startsWith(label));assert(wrapper,label);return wrapper.querySelector('input,textarea,select');}
 function set(element,value){Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element),'value').set.call(element,String(value));element.dispatchEvent(new window.Event(element.tagName==='SELECT'?'change':'input',{bubbles:true}));}
 try{
  if(surface==='dashboard'){
   window.document.querySelector('#app').outerHTML='<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create" data-home="/dashboard/studio-broadcasting"></div>';
   window.fetch=async(url,options)=>({status:'completed',result:(await window.nevaeh.execute(JSON.parse(options.body))).result});
   window.nevaeh.parseResponse=async response=>response;
  }
  window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));
  if(surface==='pwa')window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
  await until(()=>button('Render 2D preview'));
  assert(button('Render 2D preview').disabled);
  await until(()=>window.document.body.textContent.includes('2D compositor tools available.'));
  set(field('Scene prompt'),'A dragon flies');await until(()=>!button('Render 2D preview').disabled);button('Render 2D preview').click();
  await until(()=>window.document.body.textContent.includes('Use a supported scene prompt'));
  set(field('Scene prompt'),'A nighttime park with a character sitting on a bench');
  button('Generate layout').click();await until(()=>window.document.querySelector('[data-layer-id="sky"]'));
  set(field('Asset or group'),'group');
  set(field('Apply motion preset'),'float');
  set(field('Asset or group'),'sky');await until(()=>window.document.querySelector('[aria-label="Selected layer controls"]'));
  set(field('Parallax depth'),'.7');await until(()=>window.document.querySelector('[data-layer-depth="0.7"]'));
  set(field('Camera move X (%)'),0);
  set(field('Apply motion preset'),'drift_right');await until(()=>field('Motion duration (seconds)'));
  set(field('Keyframe 2 X offset (%)'),4);
  button('Add keyframe').click();await until(()=>button('Remove keyframe 2'));button('Remove keyframe 2').click();
  set(field('Preview position'),1.5);
  await until(()=>Math.abs(Number(window.document.querySelector('[data-layer-id="sky"]').dataset.motionX)-12.8)<.001);
  assert(Math.abs(Number(window.document.querySelector('[data-layer-id="sky"]').dataset.motionY)+7.2)<.001);
  button('Save scene layers').click();await until(()=>saved);assert.equal(saved.nodes[0].children[0].depth,.7);assert.equal(saved.nodes[0].children[0].motion.duration,3);assert(saved.nodes[0].motion.loop);
  await until(()=>!button('Render 2D preview').disabled);button('Render 2D preview').click();
  await until(()=>window.document.querySelector('video[src="/workflow-proof.mp4"]'));
  assert.equal(submitted.scene_id,7);assert.equal(submitted.composition.nodes[0].children[0].depth,.7);assert.equal(submitted.composition.nodes[0].children[0].motion.keyframes[1].x,.04);
  assert.deepEqual(Object.keys(submitted).sort(),['composition','request_key','scene_id']);
  assert.equal(genesisCalls,0,'Native Studio must not query Genesis');
  console.log(surface+': native layout, depth/motion edit, scrub, save, render and video return passed without Genesis');
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
(async()=>{await check('pwa');await check('dashboard');})().catch(error=>{console.error(error);process.exitCode=1;});
