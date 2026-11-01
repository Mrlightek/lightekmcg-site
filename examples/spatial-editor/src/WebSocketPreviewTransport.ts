import type {PreviewDemand,PreviewTransport} from './TimelineSync.js';
export interface PreviewSocket {readyState:number;bufferedAmount:number;send(data:string):void}
// Control messages only. Decoded video travels over the separate WebRTC media path.
export class WebSocketPreviewTransport implements PreviewTransport {
  constructor(private socket:PreviewSocket,private maxBufferedBytes=64*1024){}
  send(demand:PreviewDemand):void {
    if(this.socket.readyState!==1)throw new Error('Preview control channel is disconnected');
    if(this.socket.bufferedAmount>this.maxBufferedBytes)throw new Error('Preview control channel is congested; retaining the last displayed frame');
    this.socket.send(JSON.stringify({v:1,type:'preview.demand',session_id:demand.sessionId,
      scene_id:demand.sceneId,scene_revision:demand.sceneRevision,request_seq:demand.seq,
      frame:demand.frame,blender_frame:demand.blenderFrame,camera_ids:[demand.cameraId]}));
  }
}
