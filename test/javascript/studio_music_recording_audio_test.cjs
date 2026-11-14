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
 vm.runInThisContext(fs.readFileSync('public/lightek/studio-music-recording.js','utf8'));
 const raw=new AudioBuffer({length:44100,numberOfChannels:1,sampleRate:44100});for(let i=22050;i<44100;i++)raw.getChannelData(0)[i]=Math.sin(2*Math.PI*880*i/44100)*.25;
 const capture=new window.LightekMusicRecording.Capture();capture.take={name:'Voice take',blob:new Blob([core.wav(raw)],{type:'audio/wav'})};
 const wav=await capture.wav(),bytes=await wav.arrayBuffer(),header=new DataView(bytes);assert.equal(wav.type,'audio/wav');assert.equal(header.getUint32(24,true),48000,'recorded source is normalized to 48 kHz');assert.equal(header.getUint16(22,true),2);assert(Math.abs(header.getUint32(40,true)-48000*4)<=8,'resampling retains duration within two frames');assert.equal(await capture.wav(),wav,'normalization is cached across import retries');
 global.fetch=async()=>({ok:true,headers:{get:()=>String(bytes.byteLength)},arrayBuffer:async()=>bytes});const asset={id:88,name:'Voice take',kind:'audio',status:'ready',proxy_url:'/take',metadata:{duration:1}};
 const score=core.empty();score.bars=1;score.tempo=120;score.swing=.5;const take=core.addRecording(score,asset,.25);take.sample_in=.5;take.sample_out=1;core.syncRecordings(score);const event=core.events(score)[0];assert.equal(event.time,.125,'take placement ignores musical swing');assert.equal(event.duration,.5);
 const result=await audio.render(score,[asset]);assert(energy(result,0,.11)<1e-9,'take is silent before its placed beat');assert(energy(result,.2,.5)>.01,'recorded PCM plays from its trimmed source range');assert(energy(result,.7,.95)<energy(result,.2,.5)*1e-5,'take ends at its original source duration with only a negligible filter tail');
 const plane=result.getChannelData(0);let crossings=0;for(let i=9601;i<19200;i++)if(plane[i-1]<=0&&plane[i]>0)crossings++;assert(crossings>170&&crossings<182,'recorded pitch stays at the original 880 Hz');
 score.tempo=240;core.syncRecordings(score);assert.equal(core.events(score)[0].duration,.5,'tempo edits retain recorded source duration');assert.equal(core.events(score)[0].time,.0625,'take starts at the same musical beat after tempo edits');
 score.mixer={buses:[{id:'voice',name:'Voice',gain:0,pan:0,muted:false,solo:false,effects:[]}],master:{gain:1,effects:[]}};take.bus_id='voice';const silent=await audio.render(score,[asset]);assert(energy(silent,0,1)<1e-9,'recorded take uses the shared bus graph');score.mixer.buses[0].gain=1;
 const monitored=await Tone.Offline(async()=>{await audio.play(score,[asset],()=>{},false);},1,2,48000);audio.stop();assert(energy(monitored.get(),.2,.45)>.01,'live transport plays the recorded source');
 const phrase=core.makePattern(score);assert(phrase.tracks.every(l=>!l.notes.length),'audio takes are not copied into musical patterns');const audition=core.editor(score,phrase.id);assert.equal(core.events(audition).length,0,'pattern audition excludes song takes');
 const ensemble=core.empty();ensemble.tracks=[];const ensembleAssets=Array.from({length:9},(_,i)=>({...asset,id:i+100,proxy_url:'/take-'+i}));for(const a of ensembleAssets)core.addRecording(ensemble,a);const ensembleMix=await audio.render(ensemble,ensembleAssets);assert(energy(ensembleMix,.6,.8)>.01,'nine source-bound takes coexist beyond the shared cache capacity');
 console.log('STUDIO_MUSIC_RECORDING_AUDIO_PASS real 44.1k mono to 48k stereo WAV normalization, exact source trim/start/duration/pitch, tempo edits, group processing, live playback and pattern separation');await Tone.getContext().close();process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
