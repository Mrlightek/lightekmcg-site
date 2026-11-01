import type {EvaluatedFrame} from './timeline.js';
import type {FrameMetadata,LocalScene} from './TimelineSync.js';
interface Object3DLike {
  position:{set(x:number,y:number,z:number):unknown};
  quaternion:{set(x:number,y:number,z:number,w:number):unknown};
  scale:{set(x:number,y:number,z:number):unknown};
  updateMatrixWorld(force?:boolean):void;
}
export interface ThreeTimelinePorts {
  // Use the same coordinate adapter/root basis as the backend scene contract.
  objects:ReadonlyMap<string,Object3DLike>;
  mixers:ReadonlyArray<{setTime(seconds:number):unknown}>;
  selectShotCamera(id:string):void;
  seekMedia(media:EvaluatedFrame['media']):void;
  setGhostPicking(pending:boolean):void;
  applyPresentedMatrices(metadata:FrameMetadata):void;
}
export class ThreeTimelineAdapter implements LocalScene {
  constructor(private ports:ThreeTimelinePorts){}
  evaluate(frame:EvaluatedFrame):void {
    for(const mixer of this.ports.mixers)mixer.setTime(frame.seconds);
    for(const [id,value] of frame.transforms){
      const object=this.ports.objects.get(id);if(!object)continue;
      object.position.set(...value.position);object.quaternion.set(...value.rotation);object.scale.set(...value.scale);object.updateMatrixWorld(true);
    }
    this.ports.selectShotCamera(frame.cameraId);this.ports.seekMedia(frame.media);
  }
  setPending(pending:boolean):void {this.ports.setGhostPicking(pending);}
  alignToPresentedCamera(metadata:FrameMetadata):void {this.ports.applyPresentedMatrices(metadata);}
}
