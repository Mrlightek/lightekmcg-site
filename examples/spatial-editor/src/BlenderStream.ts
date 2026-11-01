import {SpatialSocket,type SpatialCredentials,type SpatialMessage} from './SpatialSocket.js';
export type FrameMetadata={frame_id:string;rtp_timestamp:number;captured_wall_ms:number;render_ms:number;rendered_fps:number;encode_ms:number;[key:string]:any};
export type StreamTelemetry={connection:string;pingRttMs?:number;frameRoundTripMs?:number;renderMs?:number;renderedFps?:number;encodeMs?:number;decodedFps?:number};
/** Shared by the shipped PWA and the React hook. Video pixels and metadata match by actual RTP timestamp. */
export class BlenderStream {
  socket:SpatialSocket;private peer:RTCPeerConnection|null=null;private channel:RTCDataChannel|null=null;private stopped=false;private generation=0;
  private callback=0;private timer:ReturnType<typeof setInterval>|undefined;private metadata=new Map<number,FrameMetadata>();private pending=new Map<number,number>();private lastEpoch:string|null=null;
  private stats:StreamTelemetry={connection:'idle'};private snapshots=new Map<number,Promise<ImageBitmap>>();private decoded=0;private sampleStart=performance.now();
  constructor(private video:HTMLVideoElement,credentials:()=>Promise<SpatialCredentials>,private report:(stats:StreamTelemetry)=>void,private state:(message:SpatialMessage)=>void=()=>{},private frame:(metadata:FrameMetadata,bitmap?:ImageBitmap)=>void=()=>{},private captureFrames:()=>boolean=()=>false){
    this.socket=new SpatialSocket({credentials,onStatus:connection=>{this.stats.connection=connection;report({...this.stats});},onRecovery:()=>{this.stats.connection='Scene changed. Reopen the Blender session to reconcile saved edits.';report({...this.stats});},onMessage:message=>{
      state(message);
      if(message.type==='SERVER_STATE'&&`${message.payload.server_epoch}:${this.socket.connectionGeneration}`!==this.lastEpoch){this.lastEpoch=`${message.payload.server_epoch}:${this.socket.connectionGeneration}`;void this.negotiate().catch(error=>{this.stats.connection=String(error);report({...this.stats});});}
      if(message.type==='SDP_ANSWER')void this.peer?.setRemoteDescription(message.payload as RTCSessionDescriptionInit).catch(error=>{this.stats.connection=String(error);report({...this.stats});});
    }});
  }
  async start(){this.stopped=false;this.present();await this.socket.connect();}
  private async negotiate(){
    const generation=++this.generation;this.peer?.close();this.metadata.clear();this.pending.clear();
    const peer=this.peer=new RTCPeerConnection({iceServers:this.socket.credentials?.ice_servers||[]});peer.addTransceiver('video',{direction:'recvonly'});
    peer.ontrack=event=>{if(generation!==this.generation)return;this.video.srcObject=event.streams[0]||new MediaStream([event.track]);void this.video.play().catch(()=>{this.stats.connection='Press play to view the Blender stream';this.report({...this.stats});});};
    peer.onicecandidate=event=>{if(generation!==this.generation)return;const c=event.candidate;try{this.socket.send('ICE_CANDIDATE',{candidate:c?.candidate||null,sdpMid:c?.sdpMid||null,sdpMLineIndex:c?.sdpMLineIndex??null});}catch{peer.close();}};
    const channel=this.channel=peer.createDataChannel('telemetry',{ordered:false,maxRetransmits:0});
    channel.onmessage=event=>{if(generation!==this.generation)return;try{const m=JSON.parse(event.data);
      if(m.type==='PONG')this.stats.pingRttMs=performance.now()-m.sent_ms;
      if(m.type==='FRAME_ACK')this.stats.frameRoundTripMs=m.frame_round_trip_ms;
      if(m.type==='FRAME_META'){
        this.metadata.set(m.rtp_timestamp,m);while(this.metadata.size>256)this.metadata.delete(this.metadata.keys().next().value!);
        const timestamp=this.pending.get(m.rtp_timestamp);if(timestamp!==undefined){this.pending.delete(m.rtp_timestamp);this.display(m);}
      }
      this.report({...this.stats});
    }catch{/* malformed telemetry is ignored; control has its own schema boundary */}};
    clearInterval(this.timer);this.timer=setInterval(()=>{if(channel.readyState==='open'&&channel.bufferedAmount<65536)channel.send(JSON.stringify({type:'PING',id:crypto.randomUUID(),sent_ms:performance.now()}));},1000);
    const offer=await peer.createOffer();await peer.setLocalDescription(offer);if(generation!==this.generation||this.stopped)return;
    this.socket.send('SDP_OFFER',{sdp:offer.sdp,type:'offer'});
  }
  private display(metadata:FrameMetadata){this.metadata.delete(metadata.rtp_timestamp);
    const snapshot=this.snapshots.get(metadata.rtp_timestamp);this.snapshots.delete(metadata.rtp_timestamp);
    if(snapshot)void snapshot.then(bitmap=>{if(this.stopped){bitmap.close();return;}this.frame(metadata,bitmap);}).catch(()=>{});else this.frame(metadata);
    this.stats.renderMs=metadata.render_ms;this.stats.renderedFps=metadata.rendered_fps;this.stats.encodeMs=metadata.encode_ms;
    if(this.channel?.readyState==='open'&&this.channel.bufferedAmount<65536)this.channel.send(JSON.stringify({type:'FRAME_PRESENTED',frame_id:metadata.frame_id}));
  }
  private present=()=>{if(this.stopped||!this.video.requestVideoFrameCallback)return;
    this.callback=this.video.requestVideoFrameCallback((_now,metadata)=>{
      const rtp=(metadata as VideoFrameCallbackMetadata&{rtpTimestamp?:number}).rtpTimestamp;
      if(rtp!==undefined){
        if(this.captureFrames()){
          this.snapshots.set(rtp,createImageBitmap(this.video,{imageOrientation:'flipY'}));
          while(this.snapshots.size>3){const key=this.snapshots.keys().next().value!;void this.snapshots.get(key)!.then(bitmap=>bitmap.close()).catch(()=>{});this.snapshots.delete(key);}
        }
        const frame=this.metadata.get(rtp);if(frame)this.display(frame);else {this.pending.set(rtp,performance.now());while(this.pending.size>64)this.pending.delete(this.pending.keys().next().value!);}}
      this.decoded++;const elapsed=performance.now()-this.sampleStart;if(elapsed>=1000){this.stats.decodedFps=this.decoded*1000/elapsed;this.sampleStart=performance.now();this.decoded=0;this.report({...this.stats});}
      this.present();
    });
  };
  close(){this.stopped=true;++this.generation;this.video.cancelVideoFrameCallback?.(this.callback);clearInterval(this.timer);this.socket.close();this.peer?.close();this.video.srcObject=null;this.metadata.clear();this.pending.clear();for(const bitmap of this.snapshots.values())void bitmap.then(value=>value.close()).catch(()=>{});this.snapshots.clear();}
}
