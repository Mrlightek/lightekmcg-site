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
 const score=core.empty();score.bars=1;score.tempo=120;score.tracks=[core.track('keys','Keys')];score.tracks[0].notes=[{beat:1,pitch:60,length:1,velocity:.8}];score.tracks[0].pan=-1;
 const rendered=await audio.render(score,[]);assert.equal(rendered.sampleRate,48000);assert.equal(rendered.numberOfChannels,2);assert.equal(rendered.duration,3);assert(energy(rendered,0,.45)<1e-9,'no note before the musical beat');assert(energy(rendered,.55,.9)>.01,'instrument produces audible PCM');assert(energy(rendered,.55,.9,0)>energy(rendered,.55,.9,1)*100,'track pan reaches the audio output');
 const bytes=core.wav(rendered),header=new DataView(bytes);assert.equal(header.getUint32(24,true),48000);assert.equal(header.getUint16(22,true),2);assert.equal(bytes.byteLength,44+rendered.length*4);
 score.tracks[0].muted=true;const muted=await audio.render(score,[]);assert(energy(muted,0,3)<1e-9,'muted tracks do not appear in mix');const stem=await audio.render(score,[],score.tracks[0].id);assert(energy(stem,.55,.9)>.01,'selected-track stem can be bounced independently');
 const drums=core.empty();drums.bars=1;drums.tempo=120;drums.tracks=drums.tracks.filter(t=>core.drums.includes(t.instrument));for(const t of drums.tracks)t.notes=[{beat:0,pitch:60,length:.125,velocity:.8}];const beat=await audio.render(drums,[]);assert(energy(beat,0,.4)>.01,'real drum instruments produce sound');
 const sampleBuffer=new AudioBuffer({length:48000,numberOfChannels:1,sampleRate:48000});for(let i=0;i<sampleBuffer.length;i++)sampleBuffer.getChannelData(0)[i]=Math.sin(2*Math.PI*220*i/48000)*.5;const sourceBytes=core.wav(sampleBuffer);
 global.fetch=async()=>({ok:true,headers:{get:()=>String(sourceBytes.byteLength)},arrayBuffer:async()=>sourceBytes});const sampled=core.empty();sampled.bars=1;sampled.tempo=120;sampled.tracks=[{...core.track('sample','My sample'),asset_id:88,sample_in:.1,sample_out:.5,root:60,notes:[{beat:0,pitch:60,length:.5,velocity:.8}]}];const sampler=await audio.render(sampled,[{id:88,kind:'audio',status:'ready',proxy_url:'/sample',metadata:{duration:1}}]);assert(energy(sampler,.02,.2)>.01,'uploaded slice plays through the sampler');
 const patterned=core.empty();patterned.bars=4;patterned.tempo=120;patterned.tracks=[core.track('keys','Pattern keys')];
 const phrase=core.makePattern(patterned);phrase.tracks[0].notes=[{beat:1,pitch:60,length:.5,velocity:.8}];
 patterned.playlist=[{id:'phrase-placement',pattern_id:phrase.id,bar:1,repeat:2,transpose:12,velocity:.5,muted:false}];
 const patternMix=await audio.render(patterned,[]);
 assert(energy(patternMix,0,2.45)<1e-9,'a placed pattern remains silent before its arranged beat');
 assert(energy(patternMix,2.55,2.7)>.01,'first linked pattern repeat produces PCM');assert(energy(patternMix,4.55,4.7)>.01,'second linked repeat produces PCM');
 patterned.playlist[0].muted=true;const patternMuted=await audio.render(patterned,[]);assert(energy(patternMuted,0,9)<1e-9,'muted pattern placements do not enter the WAV mix');
 score.tracks[0].muted=false;
 const monitor=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);},5,2,48000);audio.stop();const looped=monitor.get();assert(energy(looped,.65,.9)>.01,'live transport schedules notes at their musical time');assert(energy(looped,2.65,2.9)>.01,'live arrangement loops without losing note events');
 const changed=core.clone(score);changed.tracks[0].notes[0].beat=3;
 const revised=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);const transport=Tone.getTransport();transport.schedule(()=>assert(audio.update(changed)),.1);transport.schedule(()=>{const silent=core.clone(changed);silent.tracks[0].muted=true;assert(audio.update(silent));},1.8);},2,2,48000);audio.stop();assert(energy(revised.get(),.65,.9)<1e-9,'editing removes old scheduled notes while playing');assert(energy(revised.get(),1.65,1.75)>.01,'revised notes are heard without restarting the transport');assert(energy(revised.get(),1.9,2)<1e-9,'live mute silences an active instrument');
 console.log('STUDIO_MUSIC_AUDIO_PASS linked pattern WAV timing/mute and real offline synthesis and live loop/note/mixer updates, beat timing, stereo pan, mute, stem isolation, sampler slice, 48kHz WAV');
 await Tone.getContext().close();process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
