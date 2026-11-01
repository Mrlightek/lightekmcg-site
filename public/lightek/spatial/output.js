export class SpatialRecording {
  constructor(canvas,{onStatus,onReady,maxBytes=200*1024*1024,maxSeconds=180}={}) {
    this.canvas=canvas;this.onStatus=onStatus||(()=>{});this.onReady=onReady||(()=>{});
    this.maxBytes=maxBytes;this.maxSeconds=maxSeconds;this.recorder=null;this.stream=null;this.blob=null;this.url=null;this.mimeType=null;
  }
  start() {
    if(this.busy)throw new Error('Stop the current recording and wait for it to finish.');
    if(!this.canvas.captureStream||!globalThis.MediaRecorder)throw new Error('Recording is unavailable in this browser.');
    this.clear();
    this.mimeType=['video/mp4;codecs=avc1.42E01E','video/webm;codecs=vp9','video/webm;codecs=vp8','video/webm','video/mp4'].find(type=>MediaRecorder.isTypeSupported(type));
    if(!this.mimeType)throw new Error('This browser has no supported video encoder.');
    this.stream=this.canvas.captureStream(24);const chunks=[];let bytes=0;
    const recorder=this.recorder=new MediaRecorder(this.stream,{mimeType:this.mimeType,videoBitsPerSecond:4000000});
    recorder.ondataavailable=event=>{if(!event.data.size)return;chunks.push(event.data);bytes+=event.data.size;if(bytes>=this.maxBytes)this.stop();};
    recorder.onerror=()=>{this.onStatus('The browser encoder failed. Stop and try again.');this.stop();};
    recorder.onstop=()=>{
      this.busy=false;clearTimeout(this.timer);this.stream?.getTracks().forEach(track=>track.stop());this.stream=null;
      if(this.disposed)return;
      this.blob=new Blob(chunks,{type:this.mimeType.split(';')[0]});
      if(!this.blob.size){this.onStatus('No recorded video frames were produced.');return;}
      this.url=URL.createObjectURL(this.blob);
      this.onStatus('Composition recorded. Download it or save it to your Lightek library. This first recording captures video only.');this.onReady(this);
    };
    try{recorder.start(1000);this.busy=true;}catch(error){this.stream.getTracks().forEach(track=>track.stop());this.stream=null;throw error;}this.timer=setTimeout(()=>this.stop(),this.maxSeconds*1000);
    this.onStatus('Recording the composed view · video only · stops at 3 minutes or approximately 200 MB.');
  }
  stop(){if(this.recorder&&this.recorder.state!=='inactive')this.recorder.stop();}
  get filename(){return `lightek-spatial-${Date.now()}.${this.blob?.type==='video/mp4'?'mp4':'webm'}`;}
  clear(){if(this.url)URL.revokeObjectURL(this.url);this.url=null;this.blob=null;}
  dispose(){this.disposed=true;clearTimeout(this.timer);this.stop();this.stream?.getTracks().forEach(track=>track.stop());this.clear();}
}
