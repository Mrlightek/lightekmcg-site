import {cameraAt, clampFrame, evaluateFrame, normalizeProject, type EvaluatedFrame, type Project} from './timeline.js';
import type {EditorStore} from './store.js';
export interface PreviewDemand {
  v: 1; type: 'preview.demand'; sessionId: string; sceneId: number;
  sceneRevision: number; seq: number; frame: number; blenderFrame: number; cameraId: string;
}
export interface FrameMetadata {
  sessionId: string; sceneRevision: number; requestSeq: number;
  frame: number; blenderFrame: number; cameraId: string; frameId: string;
  viewMatrix: readonly number[]; projectionMatrix: readonly number[];
}
export interface DecodedFrame {
  // The receiver must associate metadata with THIS decoded frame, not just the latest side-channel message.
  metadata: FrameMetadata;
  present(): void; // Copy/upload this frame into the held compositor base layer.
  discard(): void; // Close its VideoFrame / ImageBitmap without changing visible video.
}
export interface LocalScene {
  evaluate(state: EvaluatedFrame): void;
  setPending(pending: boolean): void; // Ghost overlays; disable precise picking while background is stale.
  alignToPresentedCamera(metadata: FrameMetadata): void;
}
export interface PreviewTransport { send(demand: PreviewDemand): void }

export class TimelineSync {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private pending: PreviewDemand | undefined;
  private disposed=false;
  constructor(private store: EditorStore,private local: LocalScene,private transport: PreviewTransport,
    private sessionId: string,private intervalMs=50) {}
  seek(frame: number, final=false): number {
    if(this.disposed)throw new Error('Editor session is closed');
    const state=this.store.getState(),project=state.project;
    frame=clampFrame(frame,project);
    const seq=state.requestedSeq+1;
    this.local.evaluate(evaluateFrame(project,frame));
    this.local.setPending(true);
    this.store.setState({requestedFrame:frame,requestedSeq:seq,pending:true,lastError:null});
    this.pending={v:1,type:'preview.demand',sessionId:this.sessionId,sceneId:project.sceneId,
      sceneRevision:project.revision,seq,frame,blenderFrame:project.blenderFrameStart+frame,cameraId:cameraAt(project,frame)};
    if(final){this.flush();}
    else if(!this.timer)this.timer=setTimeout(()=>this.flush(),this.intervalMs);
    return seq;
  }
  flush(): void {
    if(this.timer)clearTimeout(this.timer);this.timer=undefined;
    const demand=this.pending;this.pending=undefined;
    if(this.disposed||!demand)return;
    try{this.transport.send(demand);}catch(error){this.store.setState({lastError:String(error),pending:true});}
  }
  acceptDecodedFrame(frame: DecodedFrame): boolean {
    const state=this.store.getState(),meta=frame.metadata;
    const matches=!this.disposed&&meta.sessionId===this.sessionId&&meta.sceneRevision===state.project.revision&&
      meta.requestSeq===state.requestedSeq&&meta.frame===state.requestedFrame&&meta.blenderFrame===state.project.blenderFrameStart+state.requestedFrame&&meta.cameraId===cameraAt(state.project,state.requestedFrame)&&
      [meta.viewMatrix,meta.projectionMatrix].every(matrix=>matrix.length===16&&matrix.every(Number.isFinite));
    if(!matches){frame.discard();return false;}
    try{
      this.local.alignToPresentedCamera(meta);
      frame.present(); // Updating a metadata label alone is not proof that those pixels are displayed.
      this.local.setPending(false);
      this.store.setState({displayedFrame:meta.frame,displayedRevision:meta.sceneRevision,pending:false,lastError:null});
      return true;
    }catch(error){frame.discard();this.store.setState({lastError:String(error),pending:true});return false;}
  }
  replaceProject(project: Project): void {
    if(this.timer)clearTimeout(this.timer);this.timer=undefined;this.pending=undefined;
    this.store.setState({project:normalizeProject(project),displayedFrame:null,displayedRevision:null});
    this.seek(this.store.getState().requestedFrame,true);
  }
  dispose(): void {this.disposed=true;if(this.timer)clearTimeout(this.timer);this.timer=undefined;this.pending=undefined;}
}
