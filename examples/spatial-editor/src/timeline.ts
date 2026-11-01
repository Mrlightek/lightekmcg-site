export type Vec3 = readonly [number, number, number];
export type Quaternion = readonly [number, number, number, number];
export interface Rate { num: number; den: number }
export interface Transform { position: Vec3; rotation: Quaternion; scale: Vec3 }
export interface Keyframe { frame: number; value: Transform; interpolation: 'linear' | 'step' }
export interface MediaClip {
  id: string; assetId: string; startFrame: number; durationFrames: number;
  sourceInFrame: number; sourceFps: Rate; gain: number;
}
export type Track =
  | { id: string; kind: 'video' | 'audio'; name: string; clips: MediaClip[]; enabled: boolean; muted: boolean }
  | { id: string; kind: 'transform'; name: string; objectId: string; keyframes: Keyframe[] }
  | { id: string; kind: 'camera'; name: string; cuts: { frame: number; cameraId: string }[] };
export interface Project {
  sceneId: number; revision: number; blenderFrameStart: number; fps: Rate; durationFrames: number;
  defaultCameraId: string; tracks: Track[];
}
export function clampFrame(frame: number, project: Project): number {
  if (!Number.isFinite(frame)) throw new Error('Timeline frame must be finite');
  return Math.max(0, Math.min(project.durationFrames - 1, Math.round(frame)));
}
export function frameToMicroseconds(frame: number, fps: Rate): bigint {
  if (!Number.isSafeInteger(frame) || frame < 0 || !Number.isSafeInteger(fps.num) || !Number.isSafeInteger(fps.den) || fps.num <= 0 || fps.den <= 0) throw new Error('Invalid integer frame or rational frame rate');
  return BigInt(frame) * BigInt(fps.den) * 1_000_000n / BigInt(fps.num);
}
export function secondsAt(frame: number, fps: Rate): number { return Number(frameToMicroseconds(frame, fps)) / 1_000_000; }
export function cameraAt(project: Project, frame: number): string {
  let camera = project.defaultCameraId, latest = -1;
  for (const track of project.tracks) if (track.kind === 'camera') for (const cut of track.cuts) {
    if (cut.frame <= frame && cut.frame >= latest) { latest = cut.frame; camera = cut.cameraId; }
  }
  return camera;
}
const lerp3 = (a: Vec3, b: Vec3, t: number): Vec3 => [a[0] + (b[0]-a[0])*t, a[1] + (b[1]-a[1])*t, a[2] + (b[2]-a[2])*t];
function slerp(a: Quaternion, b: Quaternion, t: number): Quaternion {
  let dot = a.reduce((sum, value, i) => sum + value * b[i], 0);
  const sign = dot < 0 ? -1 : 1; dot = Math.min(1, Math.abs(dot));
  const angle = Math.acos(dot), sin = Math.sin(angle);
  const wa = sin < 1e-5 ? 1-t : Math.sin((1-t)*angle)/sin;
  const wb = sin < 1e-5 ? t : Math.sin(t*angle)/sin;
  const result = a.map((value,i) => value*wa+b[i]*sign*wb);
  const length = Math.hypot(...result) || 1;
  return result.map(value => value/length) as unknown as Quaternion;
}
export function transformAt(keyframes: Keyframe[], frame: number): Transform | undefined {
  if (!keyframes.length) return undefined;
  // normalizeProject sorts once on load; binary search keeps scrubbing allocation-free here.
  const ordered = keyframes;
  let low=0,high=ordered.length;
  while(low<high){const mid=(low+high)>>>1;if(ordered[mid].frame<=frame)low=mid+1;else high=mid;}
  const next=low===ordered.length?-1:low;
  if (next === 0) return ordered[0].value;
  if (next < 0) return ordered.at(-1)!.value;
  const a = ordered[next-1], b = ordered[next];
  if (a.interpolation === 'step') return a.value;
  const t = (frame-a.frame)/(b.frame-a.frame);
  return {position:lerp3(a.value.position,b.value.position,t),rotation:slerp(a.value.rotation,b.value.rotation,t),scale:lerp3(a.value.scale,b.value.scale,t)};
}
export interface EvaluatedFrame {
  frame: number; seconds: number; cameraId: string;
  transforms: Map<string, Transform>;
  media: {clip: MediaClip; kind: 'video' | 'audio'; sourceSeconds: number; muted: boolean}[];
}
export function evaluateFrame(project: Project, frame: number): EvaluatedFrame {
  const result: EvaluatedFrame = {frame,seconds:secondsAt(frame,project.fps),cameraId:cameraAt(project,frame),transforms:new Map(),media:[]};
  for (const track of project.tracks) {
    if (track.kind === 'transform') {const value=transformAt(track.keyframes,frame);if(value)result.transforms.set(track.objectId,value);}
    if ((track.kind === 'video' || track.kind === 'audio') && track.enabled) for (const clip of track.clips) {
      if(frame>=clip.startFrame&&frame<clip.startFrame+clip.durationFrames)result.media.push({clip,kind:track.kind,muted:track.muted,
        sourceSeconds:secondsAt(clip.sourceInFrame,clip.sourceFps)+secondsAt(frame-clip.startFrame,project.fps)});
    }
  }
  return result;
}

export function normalizeProject(project:Project):Project {
  frameToMicroseconds(0,project.fps);
  if(!Number.isSafeInteger(project.blenderFrameStart))throw new Error('Blender frame start must be an integer');
  if(!Number.isSafeInteger(project.durationFrames)||project.durationFrames<1)throw new Error('A timeline needs a positive integer frame count');
  if(project.tracks.filter(track=>track.kind==='camera').length>1)throw new Error('Use one authoritative camera-cut track');
  return {...project,tracks:project.tracks.map(track=>track.kind==='transform'?{...track,keyframes:[...track.keyframes].sort((a,b)=>a.frame-b.frame)}:track.kind==='camera'?{...track,cuts:[...track.cuts].sort((a,b)=>a.frame-b.frame)}:track)};
}
