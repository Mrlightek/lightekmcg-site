// Runs the vendored instruments against a real native Web Audio offline renderer (no browser mocks).
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
(async()=>{
 global.navigator||={};await import(require.resolve('node-web-audio-api/polyfill.js'));
 window.performance=performance;global.requestAnimationFrame=window.requestAnimationFrame=()=>0;global.cancelAnimationFrame=window.cancelAnimationFrame=()=>{};window.self=window;
 global.Tone=require(process.cwd()+'/public/lightek/vendor/tone/Tone-15.1.22.js');
 Tone.setContext(new Tone.Context({context:new AudioContext({sinkId:{type:'none'}}),clockSource:'offline'}));
 // Offline rendering needs no sound-card resume; synthesis and all DSP remain real.
 Tone.start=async()=>{};global.crypto||=require('node:crypto').webcrypto;
 for(const file of ['studio-music-core','studio-music-audio'])vm.runInThisContext(fs.readFileSync('public/lightek/'+file+'.js','utf8'));
 const core=window.LightekMusicCore,audio=window.LightekMusicAudio,energy=(buffer,start,end,channel=0)=>{const data=buffer.getChannelData(channel);let sum=0;for(let i=Math.floor(start*buffer.sampleRate);i<Math.min(data.length,Math.floor(end*buffer.sampleRate));i++)sum+=data[i]**2;return sum;};
 const score=core.empty();score.version=7;score.bars=1;score.tempo=120;score.swing=0;score.tracks=[{...core.track('keys','Keys'),gain:.1,bus_id:'group',effects:[],notes:[{beat:0,pitch:72,length:3.5,velocity:.8}]}];
 const bus={id:'group',name:'Music group',gain:1,pan:0,muted:false,solo:false,effects:[]};score.mixer={buses:[bus],master:{gain:1,effects:[]}};
 const lane=(target,parameter,points)=>({...target,parameter,enabled:true,points:points.map(([beat,value,curve='hold'])=>({beat,value,curve}))});
 const dry=await audio.render(score,[]),reference=energy(dry,.65,.9);assert(reference>.001);
 score.automation=[lane({bus_id:'group'},'gain',[[0,0],[1,1],[3,0]])];
 const grouped=await audio.render(score,[]);assert(energy(grouped,.1,.4)<1e-9);assert(energy(grouped,.65,.9)>.001);assert(energy(grouped,1.65,2.5)<1e-9,'group hold envelope gates note and release tail');
 bus.muted=true;const stem=await audio.render(score,[],score.tracks[0].id);assert(energy(stem,.65,.9)>.001);assert(energy(stem,.1,.4)<1e-9,'processed stem retains bus automation while bypassing group mute');const muted=await audio.render(score,[]);assert(energy(muted,0,3)<1e-9);bus.muted=false;
 score.automation=[lane({master:true},'gain',[[0,0],[1,1],[3,0]])];const master=await audio.render(score,[]);assert(energy(master,.1,.4)<1e-9);assert(energy(master,.65,.9)>.001);assert(energy(master,1.65,2.5)<1e-9,'master envelope reaches final mix including tails');const masterStem=await audio.render(score,[],score.tracks[0].id);assert(energy(masterStem,1.65,2.5)<1e-9,'selected stems retain master fade');
 score.automation=[lane({bus_id:'group'},'gain',[[0,.5]]),lane({master:true},'gain',[[0,.5]])];const chained=await audio.render(score,[]);assert(Math.abs(energy(chained,.65,.9)/reference-.0625)<.003,'group and master gains multiply in actual PCM');
 score.automation=[lane({bus_id:'group'},'pan',[[0,-1],[2,1]])];const pan=await audio.render(score,[]);assert(energy(pan,.2,.4,0)>energy(pan,.2,.4,1)*100);assert(energy(pan,1.2,1.4,1)>energy(pan,1.2,1.4,0)*100);
 score.automation=[lane({bus_id:'group'},'gain',[[0,0,'linear'],[4,1,'linear']])];const ramp=await audio.render(score,[]);const low=energy(ramp,.45,.55)/energy(dry,.45,.55),high=energy(ramp,1.45,1.55)/energy(dry,1.45,1.55);assert(low>.05&&low<.08);assert(high>.53&&high<.6,'bus volume ramps continuously, not only at endpoints');
 score.automation[0].enabled=false;bus.gain=.5;const bypass=await audio.render(score,[]);assert(Math.abs(energy(bypass,.65,.9)/reference-.25)<.005,'bypass uses the static bus fader');bus.gain=1;
 score.automation=[lane({bus_id:'group'},'gain',[[0,0],[1,1],[3,0]]),lane({master:true},'gain',[[0,1]])];const loop=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);},5,2,48000);audio.stop();assert(energy(loop.get(),2.15,2.45)<1e-9,'loop resets bus envelope');assert(energy(loop.get(),2.7,2.9)>.001);
 const liveMute=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);Tone.getTransport().schedule(time=>{const changed=core.clone(score);changed.mixer.buses[0].muted=true;assert(audio.update(changed,time));},.2);},2,2,48000);audio.stop();assert(energy(liveMute.get(),.7,.9)<1e-9,'later automation cannot reopen a muted group');
 const liveEdit=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);Tone.getTransport().schedule(time=>{const changed=core.clone(score);changed.automation[0].points=[{beat:0,value:0,curve:'hold'}];assert(audio.update(changed,time));},.8);},2,2,48000);audio.stop();assert(energy(liveEdit.get(),1.2,1.4)<1e-9,'editing bus envelope cancels future points');
 const liveMaster=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);Tone.getTransport().schedule(time=>{const changed=core.clone(score);changed.automation[1].points=[{beat:0,value:0,curve:'hold'}];assert(audio.update(changed,time));},.8);},2,2,48000);audio.stop();assert(energy(liveMaster.get(),1.2,1.4)<1e-9,'master lane edits reach live audio');
 const liveBypass=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);Tone.getTransport().schedule(time=>{const changed=core.clone(score);changed.automation[0].enabled=false;changed.mixer.buses[0].gain=.5;assert(audio.update(changed,time));},.8);},2,2,48000);audio.stop();assert(energy(liveBypass.get(),1.7,1.8)>.0001,'bypass cancels the pending bus fade and restores base gain');
 // Pattern audition deliberately uses static group/master faders.
 const pattern=core.makePattern(score);pattern.tracks[0].notes=[{beat:0,pitch:72,length:3.5,velocity:.8}];const audition=core.editor(score,pattern.id);const phrase=await audio.render(audition,[]);assert(energy(phrase,.1,.4)>.001,'song bus automation does not leak into pattern audition');
 console.log('STUDIO_MUSIC_BUS_AUTOMATION_AUDIO_PASS real group/master hold/ramp, cumulative gain, pan, mute, processed stems, loop reset, live edits/bypass and pattern isolation');await Tone.getContext().close();process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
