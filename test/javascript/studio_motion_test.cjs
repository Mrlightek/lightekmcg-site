const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {JSDOM}=require('jsdom');
(async()=>{
 const dom=new JSDOM('<main id="app"></main>',{url:'https://studio.test/#/studio/7/cast',runScripts:'outside-only'});
 dom.window.structuredClone=structuredClone;
 const context=dom.getInternalVMContext(),evaluate=s=>vm.runInContext(s,context),document=dom.window.document;
 evaluate(`
 const app=document.getElementById('app'),requests=[];
 const object={id:10,name:'Performer',definition:{character_profile:{motions:[{id:'nod',name:'Head nod',rig:'Rig',fps:24,frame_start:1,frame_end:25}]}}};
 const record={scene:{id:7,lock_version:0,objects:[object]}};let failOnce=true,serverClips=[];
 const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const studioCurrentSceneId=()=>7,studioSceneRecord=()=>record,toast=v=>window.lastToast=v;
 const LightekStudioPerformance={capture:()=>{},busy:()=>false};
 const A={studioLoad:async()=>{object.definition.motion_clips=structuredClone(serverClips);render()}};
 const nevaeh={execute:async request=>{requests.push(structuredClone(request));if(failOnce){failOnce=false;throw Error('Connection interrupted');}serverClips=structuredClone(request.payload.clips);object.definition.motion_revision=(object.definition.motion_revision||0)+1;record.scene.lock_version++;return{result:{motion_revision:object.definition.motion_revision}};}};
 function render(){app.innerHTML=LightekStudioMotion.view(record,object)}
 `);
 vm.runInContext(fs.readFileSync('public/lightek/studio-motion.js','utf8'),context);
 const settle=async()=>{for(let i=0;i<10;i++)await new Promise(r=>setImmediate(r));};
 const click=async name=>{document.querySelector(`[data-motion=${name}]`).click();await settle();};
 const change=(name,value)=>{const input=document.querySelector(`[name="${name}"]`);input.value=value;input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));};
 const submit=async()=>{document.querySelector('[data-motion-form]').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();};
 evaluate('render()');await click('add');change('0_speed','.5');change('0_repeat','2');change('0_strength','.6');
 assert(evaluate('LightekStudioMotion.dirty()'));
 await click('duplicate');assert.equal(document.querySelector('[name="1_start"]').value,'4');
 await submit();assert.match(document.querySelector('[role=alert]').textContent,/Connection interrupted/);
 await submit();assert(!evaluate('LightekStudioMotion.dirty()'));
 const requests=JSON.parse(evaluate('JSON.stringify(requests)'));
 assert.equal(requests.length,2);assert.equal(requests[0].payload.request_key,requests[1].payload.request_key);
 assert.equal(requests[1].payload.clips[0].speed,.5);assert.equal(requests[1].payload.clips[1].start,4);assert.equal(requests[1].payload.object_id,10);
 change('0_strength','.2');await click('reload');assert.equal(document.querySelector('[name="0_strength"]').value,'0.6');assert(!evaluate('LightekStudioMotion.dirty()'));
 await click('remove');await submit();assert.equal(evaluate('serverClips.length'),1);
 assert.match(dom.window.lastToast,/saved/);
 dom.window.close();console.log('STUDIO_MOTION_DOM_PASS add retime repeat duplicate save retry reload remove');
})().catch(error=>{console.error(error);process.exit(1)});
