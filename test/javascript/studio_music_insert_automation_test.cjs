const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{JSDOM}=require('jsdom');
(async()=>{
 const dom=new JSDOM('<main id="lightek-studio-dashboard"><div id="app"></div></main>',{url:'https://studio.test/#/studio/7/music',runScripts:'outside-only'}),w=dom.window;
 const ctx=dom.getInternalVMContext(),evaluate=s=>vm.runInContext(s,ctx),document=w.document;
 evaluate(`const app=document.getElementById('app'),ST={},requests=[],played=[],record={scene:{id:7,settings:{},lock_version:0}};
 const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),studioCurrentSceneId=()=>7,studioSceneRecord=()=>record;
 const nevaeh={execute:async request=>{requests.push(JSON.parse(JSON.stringify(request)));let result={assets:[]};if(request.capability.endsWith('music.save')){record.scene.settings.music=JSON.parse(JSON.stringify(request.payload.composition));record.scene.settings.music_revision=(record.scene.settings.music_revision||0)+1;record.scene.lock_version++;result={composition:record.scene.settings.music,revision:record.scene.settings.music_revision,lock_version:record.scene.lock_version};}return{result};}};
 function render(){app.innerHTML=LightekStudioMusic.view(record)}
 window.LightekMusicAudio={stop:()=>{},play:async score=>{played.push(score);return true;},update:()=>false};`);
 vm.runInContext(fs.readFileSync('public/lightek/vendor/tone/Midi-2.0.28.js','utf8'),ctx);
 for(const name of ['studio-music-core','studio-music'])vm.runInContext(fs.readFileSync('public/lightek/'+name+'.js','utf8'),ctx);
 const settle=async()=>{for(let i=0;i<10;i++)await new Promise(r=>setImmediate(r));};
 const click=async selector=>{const element=document.querySelector(selector);assert(element,selector);element.click();await settle();};
 const change=async(selector,value)=>{const element=document.querySelector(selector);assert(element,selector);if(element.type==='checkbox')element.checked=value;else element.value=value;element.dispatchEvent(new w.Event('change',{bubbles:true}));await settle();};
 evaluate("record.scene.settings={music_mix:{asset_id:91,score_start:0},timeline:{clips:[{asset_id:91,start:3}]}};render()");await settle();
 const saved=()=>JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)')),core=w.LightekMusicCore;
 await change('[data-insert-add]','eq');await click('[data-music=save]');let score=saved(),channel=score.tracks[0],eq=channel.effects[0];
 await change('[data-automation-effect]',eq.id);assert.deepEqual([...document.querySelector('[data-automation-parameter]').options].map(o=>o.value),['low','mid','high']);
 await click('[data-music=automation-rise]');await click('[data-music=save]');score=saved();assert.equal(score.version,8);assert.equal(score.automation[0].effect_id,eq.id);assert.equal(score.automation[0].track_id,channel.id);assert.equal(score.scoring.start,3);
 await change('[data-insert-add]','delay');await click('[data-music=save]');score=saved();const delay=score.tracks[0].effects[1];
 await change('[data-automation-effect]',delay.id);await change('[data-automation-parameter]','wet');await click('[data-music=automation-fall]');await click('[data-music=save]');
 await click('[data-music=insert-up][data-index="1"]');await click('[data-music=save]');assert.equal(saved().tracks[0].effects[0].id,delay.id);assert.equal(saved().automation[1].effect_id,delay.id,'reorder retains insert identity');
 await click('[data-music=insert-remove][data-index="0"]');await click('[data-music=save]');assert.equal(saved().automation.length,1);await click('[data-music=undo]');await click('[data-music=save]');assert.equal(saved().automation.length,2);
 await change('[data-insert-enabled="0"]',false);await click('[data-music=save]');assert.equal(saved().automation.length,2,'bypass keeps envelopes');assert.equal(saved().tracks[0].effects[0].enabled,false);
 await change('[data-mix-target]','master');await change('[data-insert-add]','distortion');await click('[data-music=save]');score=saved();const dist=score.mixer.master.effects[0];
 await change('[data-automation-target]','master');await change('[data-automation-effect]',dist.id);assert.deepEqual([...document.querySelector('[data-automation-parameter]').options].map(o=>o.value),['wet']);await click('[data-music=automation-rise]');await click('[data-music=save]');assert.equal(saved().automation[2].master,true);
 await click('[data-music=add-bus]');await change('[data-insert-add]','compressor');await click('[data-music=save]');score=saved();const bus=score.mixer.buses[0],comp=bus.effects[0];await change('[data-automation-target]','bus:'+bus.id);await change('[data-automation-effect]',comp.id);await click('[data-music=automation-rise]');await click('[data-music=save]');assert.equal(saved().automation[3].bus_id,bus.id);
 await click('[data-music=remove-bus]');await click('[data-music=save]');assert.equal(saved().automation.length,3);await click('[data-music=undo]');await click('[data-music=save]');assert.equal(saved().automation.length,4);
 score=saved();for(const mutate of [s=>s.version=7,s=>s.automation[0].effect_id='missing',s=>s.automation[0].parameter='wet',s=>s.automation[2].parameter='distortion',s=>s.automation[0].points[0].value=-25]){const bad=core.clone(score);mutate(bad);assert.throws(()=>core.validate(bad));}
 await click('[data-music=new-pattern]');await click('[data-music=save]');score=saved();const audition=core.editor(core.clone(score),score.patterns[0].id);assert.equal(audition.automation.length,0);core.validate(audition);
 console.log('STUDIO_MUSIC_INSERT_AUTOMATION_DOM_PASS source v8, typed insert targets, supported parameters, stable reorder, delete/undo, bypass retention and pattern isolation');dom.window.close();
})().catch(e=>{console.error(e);process.exit(1)});
