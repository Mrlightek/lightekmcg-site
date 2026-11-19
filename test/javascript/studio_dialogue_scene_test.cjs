const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {JSDOM}=require('jsdom');
async function check(dashboard,restore=false,handoff=false){
 const dom=new JSDOM(dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create"></div>':'<div id="app"></div>',{url:'https://studio.example/#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let submitted,registration,quoted,retried=0,attempt=restore?1:0;
 const inputs={mode:'dialogue',scene_template:handoff?'counter_handoff':'studio',characters:[{name:'Sentinel',voice:'en-us',portrait_asset_id:31,colors:{skin:'#925e43',wardrobe:'#344e78',hair:'#211916'}},{name:'Beacon',voice:'en-gb',colors:{skin:'#b57955',wardrobe:'#945228',hair:'#211916'}}],turns:[{speaker:0,dialogue:'Stay alert.'},{speaker:1,dialogue:'I am ready.'}]};
 window.nevaeh={execute:async({capability,payload})=>{
  let result;switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
   case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
   case 'assets.list':result={assets:[{id:31,name:'Sentinel portrait',kind:'image',status:'ready'},{id:32,name:'Beacon portrait',kind:'image',status:'ready'},
    {id:61,name:'Prepared character',kind:'blend',status:'ready',native_url:'/character.blend',metadata:{scenes:[{name:'Rig stage',objects:[{name:'Face',definition:{shape_keys:[{name:'Basis'},{name:'Open'}]}},{name:'Armature',definition:{bones:[{name:'Head'}]}}]}]}},
    ...(registration?[{id:71,name:'Imported performer',kind:'blend',status:'ready',metadata:{character_profile:{bindings:{jaw_open:{}},motions:[{id:'point-right',name:'Point right'}]}}}]:[])]};break;
   case 'cast.register':registration=payload;result={asset_id:71,name:payload.name};break;
   case 'ai.jobs':result=[];break;
   case 'operations.list':result={operations:[],publications:[]};break;
   case 'workflow.status':result={ready:true,assets:[]};break;
   case 'ai.status':throw Error('Dialogue must not query Genesis');
   case 'character.scene.catalog':result={scene_templates:[{key:'studio',name:'Plain stage',available:true},{key:'counter_handoff',name:'Pass a parcel across the counter',available:true,dialogue_only:true}],production_templates:[],saved_templates:[],default_scene_template:'studio'};break;
   case 'character.scene.prepare':submitted=payload;attempt=1;result={operation_id:80,status:'pending',phase:'queued'};break;
   case 'character.scene.status':result=!attempt?{status:'idle'}:attempt===1?{operation_id:80,inputs,status:'failed',phase:'analyzing_speech',error:'Worker interrupted'}:{operation_id:80,inputs,status:'completed',phase:'ready',scene_id:9,cast_asset_ids:[71,72],url:'/dialogue-proof.mp4'};break;
   case 'character.scene.retry':retried++;attempt=2;result={operation_id:80,status:'pending',phase:'queued'};break;
   case 'character.scene.quote':quoted=payload;result={operation_id:82,status:'awaiting_payment',quote:{total_cents:550,currency:'USD'}};break;
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
  if(!restore){await until(()=>button('Two-character dialogue')&&!button('Two-character dialogue').disabled);button('Two-character dialogue').click();}
  await until(()=>button('Prepare dialogue scene')&&!button('Prepare dialogue scene').disabled);
  assert.equal(field('Character 2 stock voice').value,'en-gb');
  if(!handoff){
   set(field('Blender character file'),'61');await until(()=>field('Blender source scene')?.value==='Rig stage');
   const jaw=window.document.querySelector('[aria-label="Face: Jaw open"]');
   set(jaw,'1');await until(()=>!button('Save to Cast').disabled);
   button('Save to Cast').click();
   await until(()=>registration);
   assert.deepEqual({...registration.profile.bindings.jaw_open},{object:'Face',key:'Open'});
   assert.equal(registration.asset_id,61);
   await until(()=>window.document.body.textContent.includes('Prepared character is ready'));
  }
  if(restore)assert.equal(field('Character 1 portrait mask').value,'31');
  if(!restore){
   if(handoff){
    set(field('Dialogue scene setup'),'counter_handoff');
    await until(()=>window.document.body.textContent.includes('Sentinel passes the parcel to Beacon'));
    assert(field('Character 1 entrance').disabled);
    assert(!field('Character 1 facial cue').disabled);
   }
   set(field('Shot name'),'First exchange');
   set(field('Character 1 hairstyle'),'high_top');
   set(field('Character 1 portrait mask'),'31');
   set(field('Character 2 portrait mask'),'32');
   button('Add speaking turn').click();await until(()=>field('Turn 3 line'));set(field('Turn 3 line'),'Follow my lead.');
   await until(()=>!button('Prepare dialogue scene').disabled);button('Prepare dialogue scene').click();
   await until(()=>submitted);assert.equal(submitted.mode,'dialogue');assert.equal(submitted.scene_template,handoff?'counter_handoff':'studio');assert(!submitted.characters.some(row=>row.contact));assert.equal(submitted.shot_name,'First exchange');assert.equal(submitted.characters[0].hair_style,'high_top');assert.deepEqual(Array.from(submitted.characters,row=>row.portrait_asset_id),[31,32]);assert.equal(submitted.characters.length,2);assert.equal(submitted.turns.length,3);assert.equal(submitted.turns[2].speaker,0);assert.equal(submitted.turns[2].dialogue,'Follow my lead.');
  }
  await until(()=>button('Retry dialogue preparation'));button('Retry dialogue preparation').click();
  await until(()=>window.document.querySelector('video[src="/dialogue-proof.mp4"]'));assert.equal(retried,1);
  const link=[...window.document.querySelectorAll('a')].find(el=>el.textContent==='Open editable dialogue scene');assert(link.href.includes('9'));
  button('Get dialogue export price').click();await until(()=>quoted);assert.equal(quoted.operation_id,80);
  await until(()=>button('Continue to dialogue checkout'));
  button('Revise take with same cast').click();
  await until(()=>field('Character 1 performer').value==='71');
  assert.equal(field('Character 2 performer').value,'72');
  assert.equal(field('Character 1 hairstyle'),undefined);
  assert.equal(field('Character 1 portrait mask'),undefined);
  if(!handoff)set(field('Character 1 saved Blender action'),'point-right');
  set(field('Turn 1 line'),'Wait for me.');
  submitted=null;button('Prepare dialogue scene').click();
  await until(()=>submitted);
  assert.deepEqual(Array.from(submitted.characters,row=>row.cast_asset_id),[71,72]);
  assert(submitted.characters.every(row=>!row.portrait_asset_id));
  assert.equal(submitted.turns[0].dialogue,'Wait for me.');
  if(!handoff)assert.equal(submitted.characters[0].motion_action_id,'point-right');
  console.log((dashboard?'Dashboard':'PWA')+': '+(restore?'reload recovery':'three-turn submission')+', failure/retry, preview, editable link and existing quote passed');
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
(async()=>{await check(false);await check(true,false,true);await check(false,true,true);})().catch(error=>{console.error(error);process.exitCode=1;});
