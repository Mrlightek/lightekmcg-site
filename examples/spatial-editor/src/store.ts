import {createStore} from 'zustand/vanilla';
import {normalizeProject,type Project} from './timeline.js';
export interface EditorState {
  project: Project; requestedFrame: number; displayedFrame: number | null;
  requestedSeq: number; displayedRevision: number | null;
  pending: boolean; lastError: string | null;
  selection: string | null; playing: boolean; zoom: number;
}
// MediaStreams, Three.js objects, workers and RTCPeerConnections stay in adapter refs, not state.
export function createEditorStore(project: Project) {
  project=normalizeProject(project);
  return createStore<EditorState>()(()=>({project,requestedFrame:0,displayedFrame:null,requestedSeq:0,
    displayedRevision:null,pending:false,lastError:null,selection:null,playing:false,zoom:1}));
}
export type EditorStore=ReturnType<typeof createEditorStore>;
