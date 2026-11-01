import {useEffect, useMemo, useState, type ComponentType} from 'react';
import {DockviewReact, type DockviewReadyEvent} from 'dockview-react';
import {useStore} from 'zustand';
import type {EditorStore} from './store.js';
import type {TimelineSync} from './TimelineSync.js';
import 'dockview-react/dist/styles/dockview.css';
import './editor.css';

export interface EditorPanels {
  // Viewport owns a decoded-frame gate, compositor and gizmo pass with matching camera/depth.
  // Camera and AI widgets receive the real capability adapters from the app, not placeholder actions.
  viewport: ComponentType;
  cameras: ComponentType;
  library: ComponentType;
  timeline: ComponentType;
}
export function EditorShell({store,panels}:{store:EditorStore;panels:EditorPanels}) {
  const pending=useStore(store,s=>s.pending),requested=useStore(store,s=>s.requestedFrame),displayed=useStore(store,s=>s.displayedFrame);
  const error=useStore(store,s=>s.lastError);
  const [compact,setCompact]=useState(()=>typeof window!=='undefined'&&window.innerWidth<900);
  const [tab,setTab]=useState<keyof EditorPanels>('viewport');
  useEffect(()=>{const media=matchMedia('(max-width: 899px)'),update=()=>setCompact(media.matches);media.addEventListener('change',update);return()=>media.removeEventListener('change',update);},[]);
  const onReady=({api}:DockviewReadyEvent)=>{
    api.addPanel({id:'viewport',component:'viewport',title:'Stage'});
    api.addPanel({id:'library',component:'library',title:'Assets & AI',initialWidth:260,position:{referencePanel:'viewport',direction:'left'}});
    api.addPanel({id:'cameras',component:'cameras',title:'Cameras & image',initialWidth:300,position:{referencePanel:'viewport',direction:'right'}});
    api.addPanel({id:'timeline',component:'timeline',title:'Spatial timeline',initialHeight:240,position:{referencePanel:'viewport',direction:'below'}});
  };
  const Active=panels[tab];
  const components=useMemo(()=>({viewport:()=>{const Panel=panels.viewport;return <Panel/>;},cameras:()=>{const Panel=panels.cameras;return <Panel/>;},library:()=>{const Panel=panels.library;return <Panel/>;},timeline:()=>{const Panel=panels.timeline;return <Panel/>;}}),[panels]);
  return <main className="lightek-editor">
    <header><strong>LIGHTEK <span>STUDIO</span></strong><output aria-live="polite">Requested {requested} · Displayed {displayed??'—'}{pending?' · Rendering…':''}</output></header>
    {error&&<p role="alert">{error}</p>}
    {compact?<><nav aria-label="Editor workspace">{(['viewport','library','cameras','timeline'] as const).map(key=><button key={key} aria-pressed={tab===key} onClick={()=>setTab(key)}>{key}</button>)}</nav><section className="lightek-compact-panel"><Active/></section></>:
      <DockviewReact className="dockview-theme-dark" components={components} onReady={onReady}/>}
  </main>;
}
export function TimelineRuler({store,sync}:{store:EditorStore;sync:TimelineSync}) {
  const frame=useStore(store,s=>s.requestedFrame),duration=useStore(store,s=>s.project.durationFrames);
  return <label className="lightek-ruler">Frame {frame}<input aria-label="Timeline position" type="range" min={0} max={duration-1} step={1} value={frame}
    onChange={event=>sync.seek(Number(event.target.value))}
    onPointerUp={()=>sync.seek(store.getState().requestedFrame,true)}
    onKeyUp={()=>sync.seek(store.getState().requestedFrame,true)}/></label>;
}
