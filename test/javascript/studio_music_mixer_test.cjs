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
 evaluate('render()');await settle();
 await click('[data-music=add-bus]');await change('[data-mix-field="name"]','Drum group');await change('[data-insert-add]','compressor');await change('[data-insert-add]','eq');await change('[data-insert-param="low"]','-6');await click('[data-music=insert-up][data-index="1"]');await click('[data-music=save]');
 let saved=JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)')),bus=saved.mixer.buses[0];assert.equal(saved.version,4);assert.equal(bus.name,'Drum group');assert.deepEqual(bus.effects.map(e=>e.kind),['eq','compressor']);assert.equal(bus.effects[0].params.low,-6);
 await change('[data-mix-route="'+saved.tracks[0].id+'"]',bus.id);await click('[data-music=bus-mute]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.tracks[0].bus_id'),bus.id);assert.equal(evaluate('record.scene.settings.music.mixer.buses[0].muted'),true);
 await click('[data-music=remove-bus]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.tracks[0].bus_id'),null);assert.equal(evaluate('record.scene.settings.music.mixer.buses.length'),0);
 await click('[data-music=undo]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.tracks[0].bus_id'),bus.id);assert.equal(evaluate('record.scene.settings.music.mixer.buses[0].effects.length'),2);
 await change('[data-mix-target]','master');await change('[data-insert-add]','distortion');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.mixer.master.effects[0].kind'),'distortion');
 const bypass=document.querySelector('[data-insert-enabled="0"]');bypass.checked=false;bypass.dispatchEvent(new w.Event('change',{bubbles:true}));await settle();await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.mixer.master.effects[0].enabled'),false);
 await change('[data-insert-param="wet"]','2');assert(document.querySelector('[data-music-status]').textContent.includes('between'),'invalid insert edit rolls back');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.mixer.master.effects[0].params.wet'),.5);
 await change('[data-mix-target]','track');await change('[data-insert-add]','delay');await click('[data-music=automation-rise]');await click('[data-music=new-pattern]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.version'),4,'patterns and automation cannot downgrade the mixer source');
 saved=JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)'));const core=w.LightekMusicCore;core.validate(core.editor(saved,saved.patterns[0].id));assert.equal(core.editor(saved,saved.patterns[0].id).mixer.buses.length,1,'pattern monitor retains mixer routing');
 for(const mutate of [s=>s.version=3,s=>s.tracks[0].bus_id='missing',s=>s.mixer.buses[0].output='master',s=>s.mixer.master.gain=2,s=>s.mixer.master.effects[0].kind='unknown']){const bad=core.clone(saved);mutate(bad);assert.throws(()=>core.validate(bad));}
 console.log('STUDIO_MUSIC_MIXER_DOM_PASS groups, routing, insert parameters/order/bypass, undo, validation and source version compatibility');dom.window.close();
})().catch(e=>{console.error(e);process.exit(1)});
