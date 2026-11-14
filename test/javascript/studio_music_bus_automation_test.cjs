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
 const change=async(selector,value)=>{const element=document.querySelector(selector);assert(element,selector);element.value=value;element.dispatchEvent(new w.Event('change',{bubbles:true}));await settle();};
 evaluate("record.scene.settings={music_mix:{asset_id:91,score_start:0},timeline:{clips:[{asset_id:91,start:3}]}};render()");await settle();
 const saved=()=>JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)'));
 const core=w.LightekMusicCore;
 await change('[data-automation-target]','master');
 assert.deepEqual([...document.querySelector('[data-automation-parameter]').options].map(o=>o.value),['gain']);
 await click('[data-music=automation-fall]');await click('[data-music=save]');let score=saved();
 assert.equal(score.version,7);assert.equal(score.automation[0].master,true);assert.equal(score.mixer.master.gain,1);assert.equal(score.scoring.start,3,'source upgrade preserves the existing linked mix picture offset');
 await click('[data-music=add-bus]');await click('[data-music=save]');score=saved();const bus=score.mixer.buses[0],channel=score.tracks[0];
 await change('[data-mix-route="'+channel.id+'"]',bus.id);
 await change('[data-automation-target]','bus:'+bus.id);await change('[data-automation-parameter]','pan');
 assert.deepEqual([...document.querySelector('[data-automation-parameter]').options].map(o=>o.value),['gain','pan']);
 await click('[data-music=automation-rise]');await click('[data-music=save]');score=saved();
 assert.equal(score.automation[1].bus_id,bus.id);assert.equal(score.automation[1].parameter,'pan');
 assert.equal(core.automationValue(score,score.mixer.buses[0],'pan',8,{bus_id:bus.id}),0);
 await change('[data-automation-parameter]','gain');await change('[data-automation-new="beat"]','5');await change('[data-automation-new="value"]','.2');await change('[data-automation-new="curve"]','hold');await click('[data-music=automation-add]');await click('[data-music=save]');score=saved();assert.equal(score.automation[2].points[0].beat,4);
 await click('[data-music=automation-toggle]');await click('[data-music=save]');assert.equal(saved().automation[2].enabled,false);assert.equal(saved().automation[2].points.length,1);
 await click('[data-music=automation-clear]');await click('[data-music=undo]');await click('[data-music=save]');assert.equal(saved().automation.length,3);
 await click('[data-music=remove-bus]');await click('[data-music=save]');score=saved();assert.equal(score.automation.length,1);assert.equal(score.automation[0].master,true);assert.equal(score.tracks[0].bus_id,null);assert.equal(document.querySelector('[data-automation-target]').value,'track');
 await click('[data-music=undo]');await click('[data-music=save]');score=saved();assert.equal(score.automation.length,3);assert.equal(score.tracks[0].bus_id,bus.id);
 await change('[data-automation-target]','track');await click('[data-music=automation-rise]');await click('[data-music=save]');score=saved();assert.equal(score.version,7);assert.equal(score.automation.length,4);
 await click('[data-music=new-pattern]');await click('[data-music=save]');score=saved();assert.equal(score.version,7);const audition=core.editor(core.clone(score),score.patterns[0].id);assert.equal(audition.automation.length,0);core.validate(audition);
 // Channel and group IDs can coincide without aliasing envelopes or cleanup.
 const collision=core.clone(score);collision.mixer.buses[0].id=channel.id;collision.tracks[0].bus_id=channel.id;collision.automation.filter(l=>l.bus_id).forEach(l=>l.bus_id=channel.id);core.validate(collision);
 assert.notEqual(core.automationLane(collision,{bus_id:channel.id},'gain'),core.automationLane(collision,channel.id,'gain'));
 for(const mutate of [s=>s.version=6,s=>s.automation[0].master=false,s=>s.automation[0].parameter='pan',s=>s.automation[1].bus_id='missing',s=>s.automation[1].parameter='cutoff',s=>s.automation[1].track_id=channel.id,s=>s.automation.push(core.clone(s.automation[1])),s=>s.automation[1].points[0].value=-2]){const bad=core.clone(score);mutate(bad);assert.throws(()=>core.validate(bad));}
 console.log('STUDIO_MUSIC_BUS_AUTOMATION_DOM_PASS group/master targets, source v7, parameter bounds, curves/bypass, routing cleanup/undo, ID isolation and pattern audition');dom.window.close();
})().catch(e=>{console.error(e);process.exit(1)});
