export type SpatialCredentials={session_id:string;ticket:string;ws_url:string;ice_servers:RTCIceServer[];backend:string;encoder:string};
export type SpatialMessage={v:1;type:string;session_id:string;message_id:string;seq:number;scene_revision:number;payload:Record<string,any>};
export type SocketOptions={credentials:()=>Promise<SpatialCredentials>;onMessage:(message:SpatialMessage)=>void;onStatus:(status:string)=>void;onRecovery:()=>void};
/** Bounded queues: coalesce previews; retain durable edits until receipt. Never blindly replay after worker loss. */
export class SpatialSocket {
  private socket:WebSocket|null=null;private stopped=true;private ready=false;private recovery=false;private attempt=0;private sequence=0;private revision=0;
  private clientId=crypto.randomUUID();private epoch:string|null=null;private retry:ReturnType<typeof setTimeout>|undefined;private heartbeat:ReturnType<typeof setInterval>|undefined;
  private previews=new Map<string,SpatialMessage>();private commits=new Map<string,SpatialMessage>();private inflight:string|null=null;private sent=new Set<string>();private lastSeen=0;private generation=0;
  credentials:SpatialCredentials|null=null;
  get connectionGeneration(){return this.generation;}
  constructor(private options:SocketOptions){}
  async connect(){this.stopped=false;const generation=++this.generation;clearInterval(this.heartbeat);clearTimeout(this.retry);this.socket?.close();this.ready=false;
    try{const credentials=await this.options.credentials();if(this.stopped||generation!==this.generation)return;this.credentials=credentials;
      const ws=this.socket=new WebSocket(credentials.ws_url);this.options.onStatus('Connecting to Blender…');
      ws.onopen=()=>{if(generation!==this.generation)return;this.lastSeen=Date.now();this.write(this.create('HELLO',{ticket:credentials.ticket,client_id:this.clientId,known_server_epoch:this.epoch}));
        this.heartbeat=setInterval(()=>{if(Date.now()-this.lastSeen>45000)ws.close();else this.write(this.create('PING',{}));},15000);};
      ws.onmessage=event=>{if(generation!==this.generation)return;try{const m=JSON.parse(event.data) as SpatialMessage;
        if(m.v!==1||m.session_id!==credentials.session_id||!Number.isSafeInteger(m.scene_revision)||typeof m.payload!=='object')throw Error('Invalid server message');
        this.lastSeen=Date.now();this.revision=m.scene_revision;
        if(m.type==='SERVER_STATE'){
          const epoch=m.payload.server_epoch as string;
          if(this.epoch&&epoch!==this.epoch&&this.commits.size){this.recovery=true;this.inflight=null;this.options.onRecovery();}
          this.epoch=epoch;this.ready=!this.recovery;this.attempt=0;
          for(const id of m.payload.recent_receipts||[]){this.commits.delete(id);this.sent.delete(id);}
          this.inflight=null;this.options.onStatus(this.recovery?'Saved edits need reconciliation; reopen the scene before applying them again.':'Blender connected');this.flush();
        }else if(m.type==='ACK'){this.commits.delete(m.payload.command_id);this.sent.delete(m.payload.command_id);if(this.inflight===m.payload.command_id)this.inflight=null;this.flush();}
        else if(m.type==='ERROR'){
          if(['CONFLICT','RECOVERY_REQUIRED','WORKER_FAILED'].includes(m.payload.code)){this.ready=false;this.recovery=true;this.options.onRecovery();}
          this.options.onStatus(m.payload.message);
        }
        this.options.onMessage(m);
      }catch(error){this.options.onStatus(String(error));ws.close(1002);}};
      ws.onerror=()=>this.options.onStatus('Blender connection interrupted');
      ws.onclose=()=>{if(generation!==this.generation)return;this.ready=false;this.inflight=null;clearInterval(this.heartbeat);if(this.stopped)return;
        const wait=Math.min(30000,500*2**Math.min(6,this.attempt++))*(.75+Math.random()*.5);this.options.onStatus('Reconnecting to Blender…');this.retry=setTimeout(()=>void this.connect(),wait);};
    }catch(error){if(!this.stopped&&generation===this.generation){this.options.onStatus(String(error));this.retry=setTimeout(()=>void this.connect(),3000);}}
  }
  private create(type:string,payload:Record<string,any>):SpatialMessage{return {v:1,type,session_id:this.credentials?.session_id||'',message_id:crypto.randomUUID(),seq:++this.sequence,scene_revision:this.revision,payload};}
  private write(message:SpatialMessage){if(this.socket?.readyState!==WebSocket.OPEN||this.socket.bufferedAmount>128*1024)return false;this.socket.send(JSON.stringify(message));return true;}
  send(type:string,payload:Record<string,any>,key=type){
    const message=this.create(type,payload);
    if(new TextEncoder().encode(JSON.stringify(message)).byteLength>65536)throw Error('Spatial commands must fit within 64 KiB');
    if(type==='SDP_OFFER'||type==='ICE_CANDIDATE'){if(!this.ready||!this.write(message))throw Error('Signaling socket unavailable');return message.message_id;}
    if(payload.mode==='commit'){
      if(this.commits.size>=64)throw Error('Save queue full; wait for Blender to acknowledge edits');this.commits.set(message.message_id,message);
    }else{if(!this.previews.has(key)&&this.previews.size>=32)throw Error('Preview queue full');this.previews.set(key,message);}
    this.flush();return message.message_id;
  }
  private flush(){if(!this.ready)return;
    if(!this.inflight){const next=this.commits.values().next().value as SpatialMessage|undefined;if(next){if(!this.sent.has(next.message_id)){next.scene_revision=this.revision;next.session_id=this.credentials!.session_id;}if(this.write(next)){this.inflight=next.message_id;this.sent.add(next.message_id);}}}
    for(const [key,message] of this.previews){message.scene_revision=this.revision;message.session_id=this.credentials!.session_id;if(this.write(message))this.previews.delete(key);else break;}
    if((this.previews.size||(!this.inflight&&this.commits.size))&&!this.stopped)setTimeout(()=>this.flush(),50);
  }
  pendingEdits(){return [...this.commits.values()].map(message=>structuredClone(message));}
  close(){this.stopped=true;++this.generation;this.ready=false;clearTimeout(this.retry);clearInterval(this.heartbeat);this.socket?.close();this.socket=null;this.previews.clear();this.commits.clear();this.sent.clear();}
}
