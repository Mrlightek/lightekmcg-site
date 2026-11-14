/* Browser capture stays local until Save; monitoring never connects the mic to speakers. */
(() => {
  class Capture {
    constructor(changed=()=>{}){this.changed=changed;this.state='idle';this.take=null;this.error='';this.token=0;this.meter=null;}
    supported(){return !!(window.isSecureContext&&navigator.mediaDevices?.getUserMedia&&window.MediaRecorder);}
    notify(){this.changed(this);}
    release(){clearInterval(this.timer);this.timer=null;this.stream?.getTracks().forEach(t=>t.stop());this.stream=null;this.source?.disconnect();this.analyser?.disconnect();this.source=null;this.analyser=null;this.context?.close().catch(()=>{});this.context=null;this.meter=null;}
    async start(sceneId,device=''){
      if(!this.supported())throw Error('Microphone recording needs HTTPS and a browser with MediaRecorder support. Upload a recording instead.');
      if(this.state==='acquiring'||this.state==='recording'||this.state==='stopping'||this.take)throw Error('Finish, save or discard the current take first.');
      const token=++this.token;this.sceneId=sceneId;this.state='acquiring';this.elapsed=0;this.error='';this.notify();
      try{
        const Context=window.AudioContext||window.webkitAudioContext;
        if(Context){this.context=new Context();await this.context.resume();}
        if(token!==this.token)return false;
        const stream=await navigator.mediaDevices.getUserMedia({video:false,audio:{echoCancellation:false,noiseSuppression:false,autoGainControl:false,channelCount:{ideal:2},...(device?{deviceId:{exact:device}}:{})}});
        if(token!==this.token){stream.getTracks().forEach(t=>t.stop());return false;}
        this.stream=stream;
        if(this.context){this.source=this.context.createMediaStreamSource(stream);this.analyser=this.context.createAnalyser();this.analyser.fftSize=2048;this.source.connect(this.analyser);this.plane=new Float32Array(this.analyser.fftSize);}
        const mime=typeof MediaRecorder.isTypeSupported==='function'?['audio/mp4','audio/webm;codecs=opus','audio/webm','audio/ogg;codecs=opus'].find(type=>MediaRecorder.isTypeSupported(type)):null;
        const recorder=this.recorder=new MediaRecorder(stream,{...(mime?{mimeType:mime}:{}),audioBitsPerSecond:192000}),chunks=[];let bytes=0;
        recorder.ondataavailable=event=>{if(event.data?.size){chunks.push(event.data);bytes+=event.data.size;if(bytes>25*1024*1024){this.error='Recording reached the 25 MB limit.';this.stop();}}};
        recorder.onerror=event=>{this.error=event.error?.message||'Recording failed. Review or download any captured audio.';this.stop();};
        recorder.onstop=()=>{const elapsed=this.elapsed=(performance.now()-this.started)/1000;this.release();this.recorder=null;const blob=new Blob(chunks,{type:recorder.mimeType||mime||'audio/webm'});
          if(blob.size){const extension=blob.type.includes('mp4')?'m4a':blob.type.includes('ogg')?'ogg':'webm';this.take={sceneId,blob,url:URL.createObjectURL(blob),name:'Audio take',extension,elapsed,requestKey:crypto.randomUUID(),signedId:null,assetId:null,wavFile:null,placed:false};this.state='ready';}
          else{this.state='idle';this.error ||= 'No audio was captured. Try recording again.';}this.notify();};
        stream.getAudioTracks().forEach(track=>track.addEventListener('ended',()=>this.stop(),{once:true}));
        this.started=performance.now();this.state='recording';recorder.start(250);
        this.timer=setInterval(()=>{this.elapsed=(performance.now()-this.started)/1000;if(this.analyser){this.analyser.getFloatTimeDomainData(this.plane);let sum=0,peak=0;for(const value of this.plane){sum+=value*value;peak=Math.max(peak,Math.abs(value));}this.meter={rms:Math.sqrt(sum/this.plane.length),peak};}this.notify();if(this.elapsed>=120)this.stop();},100);this.notify();return true;
      }catch(error){if(token===this.token){this.release();this.state='idle';this.error=error.name==='NotAllowedError'?'Microphone permission was denied. Allow it in your browser or upload a recording.':error.message;this.notify();}throw error;}
    }
    stop(){if(this.state==='acquiring'){this.token++;this.release();this.state='idle';this.notify();return;}if(this.state==='recording'){this.state='stopping';if(this.recorder?.state!=='inactive')this.recorder.stop();this.notify();}}
    discard(){if(['acquiring','recording','stopping'].includes(this.state))throw Error('Stop recording before discarding the take.');if(this.take)URL.revokeObjectURL(this.take.url);this.take=null;this.state='idle';this.error='';this.notify();}
    async wav(){
      const take=this.take;if(!take)throw Error('Record a take first.');if(take.wavFile)return take.wavFile;
      if(take.blob.size>25*1024*1024)throw Error('This take exceeds 25 MB. Download it and trim it before importing.');
      const decoded=await Tone.getContext().decodeAudioData(await take.blob.arrayBuffer());
      if(decoded.duration<.05||decoded.duration>120.05)throw Error('Use a recording from 0.05 to 120 seconds long. Download and trim this take if needed.');
      const Offline=window.OfflineAudioContext||window.webkitOfflineAudioContext,context=new Offline(2,Math.min(120*48000,Math.round(decoded.duration*48000)),48000),source=context.createBufferSource();source.buffer=decoded;source.connect(context.destination);source.start(0);
      const buffer=await context.startRendering();take.wavFile=new File([window.LightekMusicCore.wav(buffer)],take.name.replace(/[^a-zA-Z0-9_. -]/g,'_').slice(0,100)+'.wav',{type:'audio/wav'});return take.wavFile;
    }
  }
  // Capture musical events against the audio transport, independent of browser render rate.
  class Performance {
    constructor({tempo,bars,clock,latency=0,attack=()=>{},release=()=>{}}){
      if(!Number.isFinite(tempo)||tempo<40||tempo>240||!Number.isInteger(bars)||bars<1||bars>16||!Number.isFinite(latency)||latency<0||latency>500)throw Error('Choose 1–16 bars, a supported tempo and input correction from 0–500 ms.');
      Object.assign(this,{tempo,bars,clock,latency,attack,release});this.active=new Map();this.pedal=new Set();this.events=[];this.dropped=0;this.done=false;this.last=0;
    }
    seconds(stamp){const now=this.clock();if(now!=null)this.last=now;let delta=Number.isFinite(stamp)?(stamp-performance.now())/1000:0;if(delta>0||delta<-.5)delta=0;return Math.max(0,Math.min(this.bars*4*60/this.tempo,this.last+delta-this.latency/1000));}
    on(key,pitch,velocity=0.8,channel=0,stamp){
      if(this.done||!Number.isInteger(pitch)||pitch<0||pitch>127||!Number.isFinite(velocity)||velocity<=0||velocity>1)return false;
      const seconds=this.seconds(stamp);if(seconds>=this.bars*4*60/this.tempo)return false;
      if(this.active.has(key))this.off(key,stamp,true);
      if(this.active.size>=32||this.events.length+this.active.size>=4096){this.dropped++;return false;}
      this.active.set(key,{pitch,velocity:Math.max(.01,velocity),channel,beat:seconds*this.tempo/60,down:true});this.attack(pitch,Math.max(.01,velocity));return true;
    }
    off(key,stamp,force=false){const note=this.active.get(key);if(!note)return;note.down=false;if(!force&&this.pedal.has(note.channel))return;
      const end=this.seconds(stamp)*this.tempo/60;this.active.delete(key);this.events.push({...note,length:Math.max(0,end-note.beat)});this.release(note.pitch);
    }
    sustain(channel,down,stamp){if(down)this.pedal.add(channel);else{this.pedal.delete(channel);for(const [key,n] of this.active)if(n.channel===channel&&!n.down)this.off(key,stamp,true);}}
    allOff(stamp){this.pedal.clear();for(const key of [...this.active.keys()])this.off(key,stamp,true);}
    finish(atEnd=false){if(this.done)return;const clock=this.clock;if(atEnd)this.clock=()=>this.bars*4*60/this.tempo+this.latency/1000;this.allOff();this.clock=clock;this.done=true;}
    notes(step=.25){
      if(![0,1,.5,.25,.125,.0625].includes(step))throw Error('Choose an available note grid.');const end=this.bars*4,min=step||.015625,notes=new Map();
      for(const event of this.events){const beat=Math.max(0,Math.min(end-min,step?Math.round(event.beat/step)*step:event.beat)),last=Math.min(end,Math.max(beat+min,step?Math.round((event.beat+event.length)/step)*step:event.beat+event.length)),note={beat:Number(beat.toFixed(6)),length:Number((last-beat).toFixed(6)),pitch:event.pitch,velocity:event.velocity},key=note.beat+':'+note.pitch,prior=notes.get(key);
        if(prior){prior.length=Math.max(prior.length,note.length);prior.velocity=Math.max(prior.velocity,note.velocity);}else notes.set(key,note);
      }return [...notes.values()].sort((a,b)=>a.beat-b.beat||a.pitch-b.pitch);
    }
  }
  class MidiInput {
    constructor(message=()=>{},changed=()=>{}){this.message=message;this.changed=changed;this.access=null;this.input=null;this.token=0;this.selection=0;this.listener=event=>this.message(event.data,event.timeStamp);}
    supported(){return typeof navigator.requestMIDIAccess==='function';}
    ports(){return this.access?[...this.access.inputs.values()].filter(p=>p.state==='connected'):[];}
    async connect(){if(!this.supported())throw Error('Hardware MIDI is unavailable in this browser. Use the on-screen or computer keys.');const token=++this.token,access=await navigator.requestMIDIAccess({sysex:false});if(token!==this.token)return;
      this.access=access;access.onstatechange=()=>{if(this.input?.state==='disconnected'){this.detach();this.message(new Uint8Array([176,123,0]),performance.now());}this.changed();};await this.select(this.ports()[0]?.id||'');this.changed();
    }
    detach(){if(this.input){this.input.removeEventListener('midimessage',this.listener);this.input.close?.().catch(()=>{});this.input=null;}}
    async select(id){const selection=++this.selection;this.detach();const input=this.ports().find(p=>p.id===id);if(!input){this.changed();return;}const token=this.token;await input.open();if(token!==this.token||selection!==this.selection||input.state!=='connected'){await input.close();return;}this.input=input;this.listener=event=>{if(this.input===input&&token===this.token&&selection===this.selection)this.message(event.data,event.timeStamp);};input.addEventListener('midimessage',this.listener);this.changed();}
    disconnect(){this.token++;this.selection++;this.detach();if(this.access)this.access.onstatechange=null;this.access=null;this.changed();}
  }
  window.LightekMusicRecording={Capture,Performance,MidiInput};
})();
