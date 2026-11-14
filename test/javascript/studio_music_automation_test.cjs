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
 await click('[data-music=automation-rise]');await click('[data-music=save]');
 let saved=JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)'));const core=w.LightekMusicCore;
 assert.equal(saved.version,3);assert.equal(saved.automation.length,1);assert.deepEqual(saved.automation[0].points.map(p=>p.value),[0,1.5]);
 assert.equal(core.automationValue(saved,saved.tracks[0],'gain',8),.75);assert(document.querySelector('.mw-automation-graph path.mw-automation-line').getAttribute('d').includes('L'));
 await change('[data-automation-point="curve"][data-index="1"]','hold');await click('[data-music=save]');
 saved=JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)'));assert.equal(core.automationValue(saved,saved.tracks[0],'gain',8),0);assert.equal(core.automationValue(saved,saved.tracks[0],'gain',16),1.5);
 await click('[data-music=automation-toggle]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.automation[0].enabled'),false);assert.equal(evaluate('record.scene.settings.music.automation[0].points.length'),2);
 await click('[data-music=automation-clear]');await click('[data-music=undo]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.automation.length'),1);
 await change('[data-automation-parameter]','pan');await change('[data-automation-new="beat"]','5');await change('[data-automation-new="value"]','-.5');await click('[data-music=automation-add]');await click('[data-music=save]');
 saved=JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)'));assert.equal(saved.automation[1].parameter,'pan');assert.equal(saved.automation[1].points[0].beat,4);assert.equal(core.automationValue(saved,saved.tracks[0],'pan',2),-.25,'linear interpolation from static pan before first point');
 await click('[data-music=automation-add]');assert(document.querySelector('[data-music-status]').textContent.includes('unique'),'duplicate beat rolls back');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.automation[1].points.length'),1);
 await click('[data-music=new-pattern]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.version'),3,'new pattern cannot downgrade automation source');
 const audition=core.editor(JSON.parse(evaluate('JSON.stringify(record.scene.settings.music)')),evaluate('record.scene.settings.music.patterns[0].id'));assert.equal(audition.automation.length,0,'pattern audition omits song automation');core.validate(audition);
 await click('[data-music=remove-track]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.automation.length'),0,'channel removal cleans automation references');await click('[data-music=undo]');await click('[data-music=save]');assert.equal(evaluate('record.scene.settings.music.automation.length'),2,'undo restores lanes with channel');
 for(const mutate of [s=>s.version=2,s=>s.automation[0].points[0].value=2,s=>s.automation[0].points[0].beat=17,s=>s.automation[0].parameter='unknown',s=>s.automation[0].track_id='missing',s=>s.automation[0].enabled='false']){const bad=core.clone(saved);mutate(bad);assert.throws(()=>core.validate(bad));}
 console.log('STUDIO_MUSIC_AUTOMATION_DOM_PASS lane editing, curves, bypass, persistence, validation, undo, channel cleanup, version and pattern audition');dom.window.close();
})().catch(e=>{console.error(e);process.exit(1)});
