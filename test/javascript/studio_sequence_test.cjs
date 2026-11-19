const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');const {JSDOM}=require('jsdom');
async function check(dashboard,restore=false){
 const dom=new JSDOM(dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-workspace="create"></div>':'<div id="app"></div>',{url:'https://studio.example/#/studio/7/create',runScripts:'outside-only',pretendToBeVisual:true});
 const {window}=dom;let submitted,quoted,sourceQuoted,attempt=restore?1:0,quotes=0,revised=false,replacementAvailable=!dashboard;
 const inputs={name:'Opening exchange',shots:[{operation_id:21,in:0,out:3},{operation_id:22,in:0,out:4}]};
 window.nevaeh={execute:async({capability,payload})=>{
  let result;switch(capability.replace(/^studio\.(pwa|workspace)\./,'')){
   case 'bootstrap':result={projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};break;
   case 'assets.list':result={assets:[]};break;
   case 'ai.jobs':result=[];break;
   case 'operations.list':result={operations:[],publications:[]};break;
   case 'workflow.status':result={ready:true,assets:[]};break;
   case 'ai.status':throw Error('Sequence must not query Genesis');
   case 'character.scene.catalog':result={scene_templates:[{key:'studio',name:'Plain stage',available:true}],production_templates:[],saved_templates:[],default_scene_template:'studio'};break;
   case 'character.scene.prepare':
    assert.equal(dashboard?payload.characters[0].cast_asset_id:payload.cast_asset_id,41);
    assert.equal(dashboard?payload.turns[0].dialogue:payload.dialogue,'Ready for the new scene.');
    result={operation_id:23,status:'pending'};break;
   case 'character.scene.status':if(payload.operation_id===23){revised=true;result={operation_id:23,status:'completed',scene_id:93,url:'/revised-proof.mp4'};break;}
    result=payload.operation_id===22
    ?{status:'completed',cast_asset_id:41,cast_asset_ids:[41,42],inputs:dashboard
      ?{mode:'dialogue',shot_name:'Reply',scene_template:'studio',characters:[{name:'Sentinel',voice:'en-us',colors:{skin:'#925e43',wardrobe:'#344e78',hair:'#211916'}},{name:'Beacon',voice:'en-gb',colors:{skin:'#b57955',wardrobe:'#945228',hair:'#211916'}}],turns:[{speaker:0,dialogue:'Ready.'},{speaker:1,dialogue:'I am ready.'}]}
      :{name:'Sentinel',shot_name:'Reply',dialogue:'Ready.',colors:{skin:'#925e43',wardrobe:'#344e78',hair:'#211916'}}}
    :{status:'idle'};break;
   case 'sequence.catalog':result={performances:[{operation_id:21,name:'Opening',scene_id:91,seconds:3,available:true},{operation_id:22,name:'Reply',scene_id:92,can_revise:true,seconds:4,available:true},...(revised?[{operation_id:23,name:'Reply revised',can_revise:true,seconds:dashboard?2:5,available:replacementAvailable}]:[])]};break;
   case 'sequence.prepare':submitted=payload;attempt=1;result={operation_id:80,status:'pending',inputs};break;
   case 'sequence.status':result=!attempt?{status:'idle'}:attempt===1?{operation_id:80,status:'failed',error:'Worker interrupted',inputs}:{operation_id:80,status:'completed',url:'/sequence-proof.mp4',inputs};break;
   case 'sequence.retry':attempt=2;result={operation_id:80,status:'pending',inputs};break;
   case 'sequence.quote':quoted=payload;quotes++;result=quotes===1?{status:'source_exports_required',missing:[{operation_id:21,scene_id:91,name:'Opening'}]}:quotes===2?{status:'processing_sources',asset_ids:[101,102]}:{status:'awaiting_payment',operation_id:88,edit_scene_id:93,quote:{total_cents:250,currency:'USD'}};break;
   case 'character.scene.quote':sourceQuoted=payload;result={status:'awaiting_payment',operation_id:86,quote:{total_cents:150,currency:'USD'}};break;
   default:throw Error(capability);
  }return {result};
 }};
 if(dashboard){window.fetch=async(url,options)=>({status:'completed',result:(await window.nevaeh.execute(JSON.parse(options.body))).result});window.nevaeh.parseResponse=async response=>response;}
 const button=label=>[...window.document.querySelectorAll('button')].find(el=>el.textContent===label);
 const field=label=>[...window.document.querySelectorAll('label')].find(el=>el.textContent.startsWith(label))?.querySelector('select,input,textarea');
 const set=(element,value)=>{Object.getOwnPropertyDescriptor(Object.getPrototypeOf(element),'value').set.call(element,value);element.dispatchEvent(new window.Event(element.tagName==='SELECT'?'change':'input',{bubbles:true}));};
 async function until(check){for(let i=0;i<700;i++){if(check())return;await new Promise(resolve=>setTimeout(resolve,10));}throw Error(window.document.body.textContent);}
 try{
  window.eval(fs.readFileSync(path.resolve(__dirname,'../../public/lightek/studio-unified.js'),'utf8'));if(!dashboard)window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7');
  await until(()=>button('Performed ShortCharacter · voice · cuts'));button('Performed ShortCharacter · voice · cuts').click();
  await until(()=>window.document.querySelector('[aria-label="Performance sequence editor"]'));
  const panel=window.document.querySelector('[aria-label="Performance sequence editor"]');panel.open=true;panel.dispatchEvent(new window.Event('toggle'));
  await until(()=>button('Preview sequence cut')&&!button('Preview sequence cut').disabled);
  if(!restore){
   button('Move clip 2 earlier').click();await until(()=>field('Clip 1 performance').value==='22');
   set(field('Clip 1 in'),'.5');await until(()=>Number(field('Clip 1 in').value)===.5);
   button('Revise take for clip 1').click();
   await until(()=>field('Shot name').value==='Reply');
   const performerField=dashboard?'Character 1 performer':'Reusable performer';
   const lineField=dashboard?'Turn 1 line':'Spoken line';
   assert.equal(field(performerField).value,'41');
   assert.equal(field(lineField).value,'Ready.');
   assert.equal(Number(field('Clip 1 in').value),.5);
   set(field(lineField),'Ready for the new scene.');
   button(dashboard?'Prepare dialogue scene':'Prepare performed short').click();
   await until(()=>button('Use revised take in clip 1'));
   assert.equal(field('Clip 1 performance').value,'22');
   button('Move clip 1 later').click();
   await until(()=>button('Use revised take in clip 2'));
   if(dashboard){
    button('Use revised take in clip 2').click();
    await until(()=>window.document.body.textContent.includes('The revised take needs a fresh preview'));
    assert.equal(field('Clip 2 performance').value,'22');
    replacementAvailable=true;
   }
   button('Use revised take in clip 2').click();
   await until(()=>field('Clip 2 performance').value==='23');
   assert.equal(field('Clip 1 performance').value,'21');
   assert.equal(Number(field('Clip 2 in').value),.5);
   assert.equal(Number(field('Clip 2 out').value),dashboard?2:4);
   button('Preview sequence cut').click();
   await until(()=>submitted);
   assert.deepEqual(Array.from(submitted.shots,row=>({...row})),[
    {operation_id:21,in:0,out:3},
    {operation_id:23,in:.5,out:dashboard?2:4}
   ]);
  }
  await until(()=>button('Retry sequence preview'));button('Retry sequence preview').click();await until(()=>window.document.querySelector('video[src="/sequence-proof.mp4"]'));
  assert(button('Prepare sequence export').disabled);const reviewed=field('I reviewed this sequence');reviewed.click();await until(()=>!button('Prepare sequence export').disabled);
  button('Prepare sequence export').click();await until(()=>button('Price Opening'));assert.equal(quoted.reviewed,true);button('Price Opening').click();await until(()=>sourceQuoted);assert.equal(sourceQuoted.operation_id,21);
  button('Prepare sequence export').click();await until(()=>[...window.document.querySelectorAll('a')].some(el=>el.textContent==='Open editable sequence timeline'));
  const link=[...window.document.querySelectorAll('a')].find(el=>el.textContent==='Open editable sequence timeline');assert(link.href.includes('93'));
  await until(()=>[...window.document.querySelectorAll('button')].some(el=>el.textContent.startsWith('Continue to sequence checkout')));assert.equal(quotes,3);
  console.log((dashboard?'Dashboard':'PWA')+': '+(restore?'restored saved cut':'revised, replaced, and trimmed a moved clip')+', retry, review gate, missing source quote, import polling and timeline checkout passed');
 }finally{window.LightekUnifiedStudio?.leave();window.close();}
}
(async()=>{await check(false);await check(true);await check(false,true);})().catch(error=>{console.error(error);process.exitCode=1;});
