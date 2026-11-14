/* Tone.js powers both the instrument monitor and sample-accurate offline WAV bounce. */
(() => {
  const core=window.LightekMusicCore;let live=null,serial=0;const buffers=new Map();
  function stop(){serial++;if(live){live.transport.stop();for(const id of [...live.ids,...live.noteIds])live.transport.clear(id);for(const node of live.nodes.reverse())node.dispose();live=null;}}
  async function samples(score,assets){
    // Keep a per-graph set so cache eviction cannot remove one of this song's sixteen sources.
    const prepared=new Map();
    for(const t of score.tracks.filter(t=>['sample','recording'].includes(t.instrument))){
      const a=assets.find(a=>a.id===t.asset_id);if(!a||a.kind!=='audio'||a.status!=='ready'||!a.proxy_url)throw Error('The recording is unavailable. Refresh the music library.');
      if(Number(a.metadata.duration)>120)throw Error('Use recordings up to two minutes long. Trim longer sources first.');
      const key=`${a.id}:${a.proxy_url}`;let buffer=prepared.get(key)||buffers.get(key);
      if(!buffer){const response=await fetch(a.proxy_url,{credentials:'same-origin'});if(!response.ok)throw Error('The recording could not be downloaded.');if(Number(response.headers.get('content-length'))>25*1024*1024)throw Error('Use recordings smaller than 25 MB.');const bytes=await response.arrayBuffer();if(bytes.byteLength>25*1024*1024)throw Error('Use recordings smaller than 25 MB.');buffer=await Tone.getContext().decodeAudioData(bytes);if(buffer.duration>120.001)throw Error('Use recordings up to two minutes.');if(buffers.size>=8)buffers.delete(buffers.keys().next().value);buffers.set(key,buffer);}
      if(t.sample_out>buffer.duration+.001)throw Error('The source range is outside this recording.');prepared.set(key,buffer);
    }return prepared;
  }
  function inserts(effects,output,keep){
    let input=output;for(const effect of [...(effects||[])].reverse())if(effect.enabled){
      const p=core.effectParams(effect);let node;
      if(effect.kind==='eq')node=new Tone.EQ3(p);
      else if(effect.kind==='compressor')node=new Tone.Compressor(p);
      else if(effect.kind==='distortion')node=new Tone.Distortion(p);
      else if(effect.kind==='delay')node=new Tone.FeedbackDelay(p);
      keep(node).connect(input);input=node;
    }return input;
  }
  function graph(score,assets,onlyTrack=null,monitor=false,prepared=buffers){
    const nodes=[],keep=n=>(nodes.push(n),n),voices=new Map(),controls=new Map(),busControls=new Map(),mix=core.mixerState(score);
    try{const limiter=keep(new Tone.Limiter(-1)).toDestination(),masterGain=keep(new Tone.Gain(mix.master.gain)).connect(limiter),master=inserts(mix.master.effects,masterGain,keep);
      for(const bus of mix.buses){const gate=keep(new Tone.Gain(onlyTrack||!bus.muted&&(!mix.buses.some(b=>b.solo)||bus.solo)?1:0)).connect(master),gain=keep(new Tone.Gain(bus.gain)).connect(gate),pan=keep(new Tone.Panner(bus.pan)).connect(gain),input=inserts(bus.effects,pan,keep);busControls.set(bus.id,{gate,gain,pan,input});}
    for(const t of score.tracks){if(!monitor&&(onlyTrack?t.id!==onlyTrack:!core.audible(score,t)))continue;const output=busControls.get(t.bus_id)?.input||master,gate=keep(new Tone.Gain(onlyTrack||core.audible(score,t)?1:0)).connect(output),gain=keep(new Tone.Gain(t.gain)).connect(gate),pan=keep(new Tone.Panner(t.pan)).connect(gain),input=inserts(t.effects,pan,keep),delay=keep(new Tone.FeedbackDelay({delayTime:60/score.tempo/2,feedback:0.25,wet:t.delay})).connect(input),filter=keep(new Tone.Filter(t.cutoff,'lowpass')).connect(delay);let instrument;
      if(t.instrument==='kick')instrument=keep(new Tone.MembraneSynth({pitchDecay:0.04,octaves:7,envelope:{attack:0.001,decay:0.3,sustain:0,release:0.05}}));
      else if(['snare','hat','clap'].includes(t.instrument)){const high=keep(new Tone.Filter(t.instrument==='hat'?6500:1200,'highpass')).connect(filter);instrument=keep(new Tone.NoiseSynth({noise:{type:'white'},envelope:{attack:0.001,decay:t.instrument==='hat'?0.045:0.15,sustain:0,release:0.025}}));instrument.connect(high);}
      else if(['sample','recording'].includes(t.instrument)){const a=assets.find(a=>a.id===t.asset_id),raw=prepared.get(`${a.id}:${a.proxy_url}`),first=Math.floor(t.sample_in*raw.sampleRate),last=Math.min(raw.length,Math.ceil(t.sample_out*raw.sampleRate)),slice=Tone.getContext().createBuffer(raw.numberOfChannels,last-first,raw.sampleRate);for(let i=0;i<raw.numberOfChannels;i++)slice.copyToChannel(raw.getChannelData(i).subarray(first,last),i);instrument=t.instrument==='recording'?keep(new Tone.Player({url:slice,fadeIn:.005,fadeOut:.005})):keep(new Tone.Sampler({urls:{[t.root]:slice},attack:0.005,release:0.04}));}
      else instrument=keep(new Tone.PolySynth({voice:Tone.Synth,maxPolyphony:32,options:{oscillator:{type:t.instrument==='bass'||t.instrument==='lead'?'sawtooth':t.instrument==='pad'?'sine':'triangle'},envelope:{attack:t.instrument==='pad'?0.15:0.005,decay:0.15,sustain:t.instrument==='keys'?0.2:0.65,release:t.instrument==='pad'?0.8:0.12}}}));
      if(!['snare','hat','clap'].includes(t.instrument))instrument.connect(filter);
      controls.set(t.id,{pan,gain,gate,delay,filter});voices.set(t.id,event=>{const length=Math.max(0.01,event.duration);if(t.instrument==='recording'){instrument.volume.setValueAtTime(20*Math.log10(event.velocity),event.time);instrument.start(event.time,0,length);}else if(['snare','hat','clap'].includes(t.instrument))instrument.triggerAttackRelease(Math.min(length,0.1),event.time,event.velocity);else instrument.triggerAttackRelease(t.instrument==='kick'?'C1':Tone.Frequency(event.pitch,'midi').toFrequency(),length,event.time,event.velocity);});
    }return{nodes,voices,controls,busControls,masterGain};}catch(error){nodes.reverse().forEach(n=>n.dispose());throw error;}
  }
  // Use AudioParam timing for continuous ramps; mute/solo has a separate gate.
  function automate(g,score,time,beat=0,smooth=false){
    for(const t of score.tracks){const c=g.controls.get(t.id);if(!c)continue;
      const params={gain:c.gain.gain,pan:c.pan.pan,cutoff:c.filter.frequency,delay:c.delay.wet};
      for(const [key,param] of Object.entries(params)){
        const lane=core.automationLane(score,t.id,key),value=core.automationValue(score,t,key,beat);
        if(smooth&&!lane?.enabled){param.cancelAndHoldAtTime(time);param.linearRampToValueAtTime(value,time+.02);continue;}
        param.cancelScheduledValues(time);param.setValueAtTime(value,time);
        if(lane?.enabled)for(const point of [...lane.points].sort((a,b)=>a.beat-b.beat))if(point.beat>beat){
          const at=time+(point.beat-beat)*60/score.tempo;
          if(point.curve==='linear')param.linearRampToValueAtTime(point.value,at);else param.setValueAtTime(point.value,at);
        }
      }
    }
  }
  async function play(score,assets,onTime=()=>{},loop=false){stop();const token=serial;core.validate(score);await Tone.start();const prepared=await samples(score,assets);if(token!==serial)return false;const g=graph(score,assets,null,true,prepared),transport=Tone.getTransport(),ids=[],noteIds=[];try{transport.seconds=0;transport.loop=loop;transport.loopStart=0;transport.loopEnd=core.seconds(score);g.score=score;ids.push(transport.schedule(time=>automate(g,g.score,time),0));for(const event of core.events(score))noteIds.push(transport.schedule(time=>g.voices.get(event.track)?.({...event,time}),event.time));ids.push(transport.scheduleRepeat(time=>{Tone.getDraw().schedule(()=>{if(token===serial)onTime(transport.seconds);},time);},0.05));if(!loop)ids.push(transport.schedule(time=>Tone.getDraw().schedule(()=>{if(token===serial){stop();onTime(null);}},time),Math.min(600,core.seconds(score)+core.mixerTail(score))));live={...g,graph:g,transport,ids,noteIds,tempo:score.tempo,topology:core.mixerTopology(score)};transport.start('+0.05');return true;}catch(e){[...ids,...noteIds].forEach(id=>transport.clear(id));g.nodes.reverse().forEach(n=>n.dispose());throw e;}}
  function update(score,time=Tone.now()){
    if(!live)return false;core.validate(score);
    const topology=core.mixerTopology(score);if(topology!==live.topology)return false;
    const mix=core.mixerState(score);live.masterGain.gain.rampTo(mix.master.gain,.02,time);
    for(const bus of mix.buses){const c=live.busControls.get(bus.id);c.gain.gain.rampTo(bus.gain,.02,time);c.pan.pan.rampTo(bus.pan,.02,time);c.gate.gain.rampTo(!bus.muted&&(!mix.buses.some(b=>b.solo)||bus.solo)?1:0,.02,time);}
    for(const t of score.tracks){const c=live.controls.get(t.id);c.gate.gain.rampTo(core.audible(score,t)?1:0,0.02,time);c.delay.delayTime.rampTo(60/score.tempo/2,0.02,time);}
    const seconds=live.transport.getSecondsAtTime(time)*live.tempo/score.tempo;live.transport.loopEnd=core.seconds(score);if(live.tempo!==score.tempo||seconds>=core.seconds(score))live.transport.seconds=seconds%core.seconds(score);live.tempo=score.tempo;live.graph.score=score;automate(live,score,time,(seconds%core.seconds(score))*score.tempo/60,true);
    live.noteIds.forEach(id=>live.transport.clear(id));live.noteIds=core.events(score).map(event=>live.transport.schedule(time=>live?.voices.get(event.track)?.({...event,time}),event.time));return true;
  }
  async function render(score,assets,onlyTrack=null){stop();core.validate(score);await Tone.start();const prepared=await samples(score,assets);let g;try{const result=await Tone.Offline(()=>{g=graph(score,assets,onlyTrack,false,prepared);automate(g,score,0);for(const event of core.events(score,onlyTrack))g.voices.get(event.track)?.(event);},Math.min(600,core.seconds(score)+core.mixerTail(score)),2,48000);return result.get();}finally{g?.nodes.reverse().forEach(n=>n.dispose());}}
  window.LightekMusicAudio={play,stop,render,update,position:()=>live?live.transport.seconds:null,unlock:()=>Tone.start()};
})();
