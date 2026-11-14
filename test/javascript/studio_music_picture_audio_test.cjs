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
 const score=core.empty();score.version=6;score.scoring={start:3,cues:[]};score.bars=1;score.tempo=120;score.tracks=[{...core.track('keys'),notes:[{beat:0,pitch:60,length:.5,velocity:.8}]}];const positions=[];
 const result=await Tone.Offline(async()=>{await audio.play(score,[],()=>{},true);Tone.getTransport().schedule(()=>positions.push(audio.position()),.25);Tone.getTransport().schedule(()=>positions.push(audio.position()),.75);},3,2,48000);audio.stop();assert(positions.length>=3);assert(Math.abs(positions[0]-.25)<.02);assert(Math.abs(positions[1]-.75)<.02);assert(positions.some((value,index)=>index>0&&positions[index-1]>.7&&value<.3),'picture clock resets with the real music loop');assert.equal(audio.position(),null,'stopping releases the picture reference clock');assert(energy(result.get(),.1,.2)>.01);assert(Math.abs(core.scoreStart(score,{settings:{}})+positions[0]-3.25)<.02);console.log('STUDIO_MUSIC_PICTURE_AUDIO_PASS real music transport phase, loop reset, score-offset mapping and stop');await Tone.getContext().close();process.exit(0);
})().catch(e=>{console.error(e);process.exit(1)});
