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
  window.LightekMusicRecording={Capture};
})();
