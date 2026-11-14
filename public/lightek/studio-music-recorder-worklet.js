/* PCM recording in the backing track's AudioContext. Output is always silent. */
class LightekTakeRecorder extends AudioWorkletProcessor {
  constructor(options){
    super();const config=options.processorOptions||{};this.stopFrame=Math.floor(config.stopFrame);this.maxFrames=Math.min(120*sampleRate,Math.floor(config.maxFrames||120*sampleRate));
    if(!Number.isFinite(this.stopFrame)||this.stopFrame<0||this.maxFrames<=0)throw Error('Invalid recording frame bounds');
    this.left=new Float32Array(2048);this.right=new Float32Array(2048);this.used=0;this.frames=0;this.first=null;this.last=null;this.done=false;
    this.port.onmessage=event=>{if(event.data?.type==='stop')this.finish('stopped');};
  }
  flush(){if(!this.used)return;const left=this.left.slice(0,this.used),right=this.right.slice(0,this.used);this.port.postMessage({type:'pcm',frame:this.chunkFrame,channels:[left.buffer,right.buffer]},[left.buffer,right.buffer]);this.used=0;}
  finish(reason){if(this.done)return;this.done=true;this.flush();this.port.postMessage({type:'done',firstFrame:this.first,lastFrame:this.last,frames:this.frames,reason});}
  process(inputs,outputs){
    for(const channel of outputs[0]||[])channel.fill(0);
    if(this.done)return false;const input=inputs[0];
    if(!input?.[0]?.length){if(this.first!==null||currentFrame>=this.stopFrame)this.finish('input-ended');return !this.done;}
    const count=Math.max(0,Math.min(input[0].length,this.stopFrame-currentFrame,this.maxFrames-this.frames));
    if(count&&this.first===null)this.first=currentFrame;
    for(let i=0;i<count;i++){if(!this.used)this.chunkFrame=currentFrame+i;this.left[this.used]=input[0][i];this.right[this.used]=(input[1]||input[0])[i];this.used++;this.frames++;this.last=currentFrame+i+1;if(this.used===2048)this.flush();}
    if(this.frames>=this.maxFrames||currentFrame+count>=this.stopFrame)this.finish('window-ended');return !this.done;
  }
}
registerProcessor('lightek-take-recorder',LightekTakeRecorder);
