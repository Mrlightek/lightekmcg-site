import React, {useCallback,useEffect,useMemo,useRef,useState} from 'react';
import {createRoot} from 'react-dom/client';
import {Download, Film, FolderOpen, Plus, Share2, Sparkles} from 'lucide-react';
import {pending, progressLabel,uploadMessage, requestKey, sceneRecords, studioApi} from './api';
import {Creation, Preview} from './create';
import {Publish} from './publish';
import {Assistant} from './assistant';

const workspaces = [
  ['create',Sparkles,'AI Studio Create'],['timeline',Film,'Timeline & Edit'],
  ['library',FolderOpen,'Media Library'],['publish',Share2,'Social & Publish']
];
const aliases={ai:'create',workflows:'create',stage:'create',edit:'timeline',color:'timeline',assets:'library',media:'library',deliver:'publish',cast:'create'};
const tabFor=input=>workspaces.some(([name])=>name===input)?input:aliases[input]||'timeline';
function readTimeline(value) {
  return {
    output:'video',width:1280,height:720,fps:24,...value,
    clips:Array.isArray(value?.clips) ? value.clips.filter(clip=>clip && typeof clip==='object') : []
  };
}
const formats={portrait:[1080,1920],square:[1080,1080],landscape:[1920,1080]};
const videoKinds=['audio','image','video'];

function clipLength(clip){return (clip.out-clip.in)/(clip.speed||1);}
function duration(asset){return asset.kind==='image'?5:Number(asset.metadata?.duration);}
let activeHash;
function changeRoute(scene,tab){
  activeHash=scene?`#/studio/${scene}/${tab}`:'#/studio';
  history.replaceState(history.state,'',location.pathname+location.search+activeHash);
}

function Timeline({timeline, update, assets, save, busy, dirty, selected, onSelect, go, advanced}) {
  const [index,setIndex]=useState(0);
  const clip=timeline.clips[index];
  const current=assets.find(asset=>asset.id===(clip?.asset_id || selected));
  const tracks=[...new Set(timeline.clips.map(item=>item.track || 0))].sort((a,b)=>a-b);
  function edit(key,value){
    update({...timeline,clips:timeline.clips.map((item,i)=>i===index?{...item,[key]:value}:item)});
  }
  function remove(){
    update({...timeline,clips:timeline.clips.filter((_,i)=>i!==index)});
    setIndex(Math.max(0,index-1));
  }
  return <div className="ls-edit">
    <Preview asset={current} title="Timeline clip preview"/>
    <div className="ls-row"><strong>Timeline</strong><span>{dirty?'Unsaved changes':'Saved'}</span>
      <button onClick={()=>go('library')}>Add media</button><button className="ls-primary" disabled={!dirty||busy} onClick={save}>Save edit</button></div>
    <div className="ls-card ls-timeline">{tracks.map(track=><div className="ls-track" key={track}>
      <strong>{timeline.tracks?.find(item=>item.id===track)?.name || `Track ${track+1}`}</strong>
      <div className="ls-strip">{timeline.clips.map((item,i)=>(item.track || 0)===track&&<button key={i} aria-pressed={i===index} onClick={()=>{setIndex(i);onSelect(item.asset_id);}}>
        <span>{assets.find(asset=>asset.id===item.asset_id)?.name || `Clip ${i+1}`}</span><small>{Number(item.start).toFixed(2)}s · {clipLength(item).toFixed(2)}s</small></button>)}</div>
    </div>)}
      {!timeline.clips.length&&<p>Import a photo or video, or add a generated clip.</p>}
    </div>
    {clip&&<div className="ls-card ls-fields">
      {[['start','Timeline start'],['in','Trim in'],['out','Trim out'],['track','Track']].map(([key,label])=><label key={key}>{label}<input type="number" min="0" max={key==='track'?15:600} step={key==='track'?1:.01} value={clip[key]} onChange={event=>edit(key,Number(event.target.value))}/></label>)}
      <button onClick={remove}>Remove clip</button>
    </div>}
    <div className="ls-row"><label>Frame size <select value={Object.keys(formats).find(name=>Math.abs(timeline.width/timeline.height-formats[name][0]/formats[name][1])<.01)||''} onChange={event=>{const [width,height]=formats[event.target.value];update({...timeline,output:'video',width,height});}}>
      <option value="" disabled>Custom</option><option value="landscape">16:9 Landscape</option><option value="portrait">9:16 Portrait</option><option value="square">1:1 Square</option>
    </select></label><a href={advanced}>Open advanced timeline editor</a></div>
  </div>;
}

function Library({assets, selected, onSelect, upload, add, busy, next, more, retry, renders, openRender}) {
  const [query,setQuery]=useState('');
  const [filter,setFilter]=useState('all');
  const shown=assets.filter(item=>(filter==='all'||item.kind===filter)&&item.name.toLowerCase().includes(query.toLowerCase()));
  const media=assets.find(item=>item.id===selected);
  return <div className="ls-library">
    <div className="ls-row"><label className="ls-upload"><Plus size={16}/> Import media<input type="file" accept="image/*,video/*,audio/*,.heic,.heif,.avif,.blend,.glb" disabled={busy} onChange={event=>{const file=event.target.files[0];event.target.value='';if(file)upload(file);}}/></label>
      <input aria-label="Search media" placeholder="Search media" value={query} onChange={event=>setQuery(event.target.value)}/>
      <select aria-label="Filter media by type" value={filter} onChange={event=>setFilter(event.target.value)}><option value="all">All media</option><option value="video">Videos</option><option value="image">Images</option><option value="audio">Audio</option><option value="blend">Character rigs</option></select>
    </div>
    {media&&videoKinds.includes(media.kind)&&<Preview asset={media} title="Media preview"/>}
    <div className="ls-assets">{shown.map(item=><article className="ls-card" key={item.id}>
      <button aria-pressed={selected===item.id} onClick={()=>onSelect(item.id)}>{item.thumbnail_url&&<img src={item.thumbnail_url} alt=""/>}<strong>{item.name}</strong><small>{item.kind} · {progressLabel(item.status)}</small></button>
      {item.status==='failed'&&<button disabled={busy} onClick={()=>retry(item.id)}>Retry import</button>}
      {item.status==='ready'&&videoKinds.includes(item.kind)&&<button disabled={busy} onClick={()=>add(item.id)}>Add to timeline</button>}
    </article>)}</div>
    {!shown.length&&<p className="ls-muted">No media matches this view.</p>}
    {next&&<button onClick={()=>more(next)}>Load more media</button>}
    {!!renders.length&&<section className="ls-library" aria-label="Renders">
      <h2>Renders</h2>
      <div className="ls-assets">{renders.map(item=><article className="ls-card" key={item.id}>
        <button onClick={()=>openRender(item.id)} disabled={busy}>
          <strong>{item.output?.fit==='cover'?'9:16 clip':item.type==='build_scene'?'3D movie':'Timeline export'}</strong>
          <small>{item.cpu_resumable?'Recoverable':progressLabel(item.status)}</small>
        </button>
      </article>)}</div>
    </section>}
  </div>;
}

function Workspace({api,record,initialTab,initialAsset,projects,selectScene,home,updateScene,openCampaign}) {
  const {project,scene}=record;
  const [tab,setTab]=useState(tabFor(initialTab));
  const [saved,setSaved]=useState(()=>readTimeline(scene.settings?.timeline));
  const [timeline,setTimeline]=useState(saved);
  const [revision,setRevision]=useState(scene.lock_version);
  const [selected,setSelected]=useState(initialAsset || null);
  const [operationId,setOperationId]=useState(null);
  const [assets,setAssets]=useState([]);
  const [next,setNext]=useState(null);
  const [jobs,setJobs]=useState([]);
  const [localActivity,setLocalActivity]=useState([]);
  useEffect(()=>api.onActivity(item=>{
    if(item.scene_id!==scene.id)return;
    setLocalActivity(rows=>[{...rows.find(row=>row.id===item.id),...item},...rows.filter(row=>row.id!==item.id&&row.id!==item.replace)].slice(0,40));
  }),[api,scene.id]);
  const [ops,setOps]=useState({operations:[],publications:[]});
  const [inventory,setInventory]=useState(null);
  const [inventoryError,setInventoryError]=useState(false);
  const [inventoryAttempt,setInventoryAttempt]=useState(0);
  const [referenceAssets,setReferenceAssets]=useState([]);
  const [publishLoaded,setPublishLoaded]=useState(tab==='publish');
  const [createLoaded,setCreateLoaded]=useState(tab==='create');
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState('');
  const [message,setMessage]=useState('');
  const [waiting,setWaiting]=useState(initialAsset || null);
  const executing=useRef(false);
  const alive=useRef(true);
  const loadId=useRef(0);
  const dirty=JSON.stringify(saved)!==JSON.stringify(timeline);
  useEffect(()=>{alive.current=true;return()=>{alive.current=false;};},[]);
  const refresh=useCallback(async ()=>{
    const id=++loadId.current;
    const [library,generation,delivery,references]=await Promise.allSettled([
      api.call('assets.list',{scope_site:true}), api.call('ai.jobs',{scene_id:scene.id}), api.call('operations.list',{project_id:project.id,...(!api.dashboard?{activity_scene_id:scene.id}:{})}), api.call('assets.list',{surface:'ai_input',scope_site:true})
    ]);
    if(!alive.current||id!==loadId.current)return;
    if(library.status==='fulfilled'&&Array.isArray(library.value?.assets)){
      setAssets(previous=>[...library.value.assets,...previous.filter(item=>!library.value.assets.some(next=>next.id===item.id))]);
      setNext(library.value.next_before);
    } else setError('The Media Library is temporarily unavailable.');
    if(references.status==='fulfilled'&&Array.isArray(references.value?.assets))setReferenceAssets(references.value.assets);
    if(generation.status==='fulfilled'&&Array.isArray(generation.value))setJobs(generation.value);
    if(delivery.status==='fulfilled'&&Array.isArray(delivery.value?.operations)&&Array.isArray(delivery.value?.publications))setOps(delivery.value);
  },[api,scene.id,project.id]);

  useEffect(()=>{refresh();},[refresh]);
  const persisted=ops.activity || [];
  const activity=[...localActivity.filter(row=>!persisted.some(item=>item.id===row.id)),...persisted];
  const working=!!waiting || [...activity,...assets,...jobs,...ops.operations,...ops.publications].some(item=>pending(item.status));
  useEffect(()=>{
    if(!working&&tab!=='publish')return;
    const timer=setInterval(refresh,4000);
    return()=>clearInterval(timer);
  },[working,tab,refresh]);
  useEffect(()=>{
    if(tab!=='create')return;
    let active=true;
    const load=async()=>{
      try {
        const status=await api.call('ai.status',{scene_id:scene.id});
        if(!status || !Array.isArray(status.genesis_workers) || !Array.isArray(status.render_pools) || !Array.isArray(status.performances)){
          throw Error('Incomplete worker status.');
        }
        if(active){setInventory(status);setInventoryError(false);}
      }catch{
        if(active){setInventory(null);setInventoryError(true);}
      }
    };
    load();
    const timer=setInterval(load,20000);
    return()=>{active=false;clearInterval(timer);};
  },[api,scene.id,tab,inventoryAttempt]);
  const clipIds=timeline.clips.map(clip=>clip.asset_id).join(',');
  useEffect(()=>{
    if(!clipIds)return;
    let active=true;
    api.call('assets.list',{asset_ids:[...new Set(clipIds.split(',').map(Number))]}).then(result=>{
      if(active&&Array.isArray(result?.assets))setAssets(items=>[...items,...result.assets.filter(item=>!items.some(old=>old.id===item.id))]);
    }).catch(()=>{});
    return()=>{active=false;};
  },[api,clipIds]);
  useEffect(()=>{
    if(!dirty&&!busy)return;
    const warn=event=>{event.preventDefault();event.returnValue='';};
    addEventListener('beforeunload',warn);
    return()=>removeEventListener('beforeunload',warn);
  },[dirty,busy]);
  function go(nextTab){
    if(nextTab==='publish')setPublishLoaded(true);
    if(nextTab==='create')setCreateLoaded(true);
    setTab(nextTab);
    changeRoute(scene.id,nextTab);
  }
  function run(action) {
    if(executing.current)return;
    executing.current=true;setBusy(true);setError('');setMessage('');
    return Promise.resolve().then(action).catch(error=>{if(error.name!=='AbortError'&&alive.current)setError(error.message);})
      .finally(()=>{executing.current=false;if(alive.current)setBusy(false);});
  }
  async function save(value=timeline){
    if(JSON.stringify(value)===JSON.stringify(saved))return;
    const updated=await api.call('timeline.save',{scene_id:scene.id,lock_version:revision,timeline:value});
    const normalized=readTimeline(updated.timeline);
    setRevision(updated.lock_version);setSaved(normalized);setTimeline(normalized);
    updateScene(scene.id,{lock_version:updated.lock_version,settings:{...scene.settings,timeline:normalized}});
    setMessage('Edit saved.');
  }
  async function add(id){
    const asset=assets.find(row=>row.id===id);
    if(!asset||asset.status!=='ready'||!Number.isFinite(duration(asset))||duration(asset)<=0)throw Error('Wait for the media preview to finish.');
    const track=asset.kind==='audio'?1:0;
    const end=Math.max(0,...timeline.clips.filter(clip=>clip.track===track).map(clip=>clip.start+clipLength(clip)));
    const length=Math.min(600-end,duration(asset));
    if(length<=0||timeline.clips.length>=64)throw Error('This timeline is full.');
    const updated={...timeline,clips:[...timeline.clips,{asset_id:asset.id,track,start:end,in:0,out:length,gain:1}]};
    setTimeline(updated);setSelected(id);
    go('timeline');
    await save(updated);
  }
  useEffect(()=>{
    if(!waiting||busy)return;
    function completeHandoff(){
      const url=new URL(location.href);
      if(url.searchParams.get('edit_asset')===String(waiting)){
        url.searchParams.delete('edit_asset');
        history.replaceState(history.state,'',url);
      }
    }
    if(timeline.clips.some(clip=>clip.asset_id===waiting)){setWaiting(null);completeHandoff();return;}
    const asset=assets.find(item=>item.id===waiting);
    if(asset?.status==='failed'){setError(asset.error || 'Media preparation failed. Retry in the Media Library.');setWaiting(null);}
    if(asset?.status==='ready'){setWaiting(null);run(async()=>{await add(waiting);completeHandoff();});}
  },[waiting,busy,assets,timeline]);
  async function upload(file){
    let result;
    try {result=await api.upload(file,project.id);}
    catch(error){throw Error(uploadMessage(error));}
    setSelected(result.asset_id);
    setMessage('Original saved. Preparing the preview.');
    await refresh();
  }
  const activeLabel=workspaces.find(([name])=>name===tab)[2];

  return <div className="ls-shell">
    <aside className="ls-sidebar">
      <div className="ls-brand"><span>L</span><div><strong>LIGHTEK STUDIO</strong><small>Create, edit, score and publish</small></div></div>
      <nav aria-label="Studio workspaces">{workspaces.map(([name,Icon,label])=><button type="button" key={name} aria-current={tab===name?'page':undefined} onClick={()=>go(name)} disabled={busy}><Icon size={17}/>{label}</button>)}</nav>
      <nav aria-label="More Studio tools">
        <a href={api.native(scene.id,'music')} onClick={event=>{if(busy || dirty&&!window.confirm('Open Music and discard unsaved timeline changes?'))event.preventDefault();}}>Music &amp; audio</a>
        <a href={api.native(scene.id,'stage')} onClick={event=>{if(busy || dirty&&!window.confirm('Open Animation and discard unsaved timeline changes?'))event.preventDefault();}}>Animation &amp; characters</a>
        {api.dashboard&&<a href={api.editor('photo')} onClick={event=>{if(busy || dirty&&!window.confirm('Open Photo Studio and discard unsaved timeline changes?'))event.preventDefault();}}>Photo &amp; graphics</a>}
        {api.dashboard&&<a href={api.editor('video')} onClick={event=>{if(busy || dirty&&!window.confirm('Open Video Studio and discard unsaved timeline changes?'))event.preventDefault();}}>Full video editor</a>}
      </nav>
      <a className="ls-exit" href={home}>Exit Studio</a>
    </aside>
    <main className="ls-main">
      <header className="ls-header"><h1>{activeLabel}</h1><label><span className="ls-sr">Project and scene</span>
        <select value={scene.id} disabled={busy} onChange={event=>{if(!dirty||window.confirm('Switch scenes and discard unsaved timeline changes?'))selectScene(Number(event.target.value),tab);}}>
          {projects.map(item=><option key={item.scene.id} value={item.scene.id}>{item.project.name} · {item.scene.name}</option>)}
        </select></label>
        <button onClick={()=>{if(!dirty||window.confirm('Leave this scene and discard unsaved timeline changes?'))selectScene(null,tab);}} disabled={busy}>Projects</button>
        <button className="ls-primary" disabled={busy} onClick={()=>{go('publish');requestAnimationFrame(()=>document.getElementById('ls-export')?.scrollIntoView({block:'start'}));}}><Download size={16}/> Export MP4</button>
        {!api.dashboard&&<Assistant api={api} project={project} scene={scene} tab={tab}
          assetId={assets.some(item=>item.id===selected)?selected:null} artifactId={typeof selected==='string'&&/^render-\d+$/.test(selected)?Number(selected.slice(7)):null} activity={activity} refresh={refresh}
          openCampaign={id=>id?openCampaign(id):go('publish')} openResult={item=>{
            if(item.asset_id){setSelected(item.asset_id);go('library');}
            else {setOperationId(item.operation_id);go('create');}
          }} resume={id=>run(async()=>{await api.call('render.resume',{operation_id:id});await refresh();})}/>}
      </header>
      <div className="ls-content">
        {error&&<p className="ls-error" role="alert">{error}</p>}
        {(message||waiting)&&<p className="ls-notice" role="status">{message || 'Preparing your media for the timeline.'}</p>}
        {createLoaded&&<div hidden={tab!=='create'}><Creation {...{api,project,scene:{...scene,lock_version:revision},assets,referenceAssets,inventory,inventoryError,retryInventory:()=>{setInventoryError(false);setInventoryAttempt(attempt=>attempt+1);},jobs,operations:ops.operations,selected,onSelect:setSelected,add:id=>run(()=>add(id)),refresh,timeline,go,run,busy,operationId,setOperationId,onRevision:lock_version=>{setRevision(lock_version);updateScene(scene.id,{lock_version});}}}/></div>}
        {tab==='timeline'&&<Timeline {...{timeline,update:setTimeline,assets,save:()=>run(()=>save()),busy,dirty,selected,onSelect:setSelected,go,advanced:api.advanced(scene.id)}}/>}
        {tab==='library'&&<Library {...{assets,selected,onSelect:setSelected,busy,next,upload:file=>run(()=>upload(file)),add:id=>run(()=>add(id)),
          renders:ops.operations.filter(item=>item.scene_id===scene.id&&!item.draft_preview&&['build_scene','edit_media'].includes(item.type)),
          openRender:id=>{setOperationId(id);go('create');},
          retry:id=>run(async()=>{await api.call('asset.retry',{asset_id:id});await refresh();}),
          more:before=>run(async()=>{const result=await api.call('assets.list',{scope_site:true,before});setAssets(items=>[...new Map([...items,...result.assets].map(item=>[item.id,item])).values()]);setNext(result.next_before);})}}/>}
        {publishLoaded&&<div hidden={tab!=='publish'}><Publish {...{api,project,scene,active:tab==='publish',clips:assets,operations:ops.operations,publications:ops.publications,selected,onSelect:setSelected,timeline,save,run,busy,refresh}}/></div>}
      </div>
    </main>
  </div>;
}

export default function LightekUnifiedStudio({api,route,home}) {
  const [projects,setProjects]=useState([]);
  const [selected,setSelected]=useState(route.scene);
  const [initialTab,setInitialTab]=useState(route.tab);
  const [load,setLoad]=useState('loading');
  const [error,setError]=useState('');
  const [name,setName]=useState('');
  const [creating,setCreating]=useState(false);
  const [key,setKey]=useState(requestKey);
  const [entry,setEntry]=useState('timeline');
  const loadProjects=useCallback(async()=>{
    try {const result=await api.call('bootstrap');setProjects(sceneRecords(result.projects));setLoad('ready');}
    catch(error){setError(error.message);setLoad('failed');}
  },[api]);
  useEffect(()=>{loadProjects();},[loadProjects]);
  const record=projects.find(item=>item.scene.id===selected);
  async function openCampaign(id){
    const result=await api.call('bootstrap');
    const records=sceneRecords(result.projects);
    if(!records.some(item=>item.scene.id===id))return;
    setProjects(records);selectScene(id,'publish');
  }
  function selectScene(id,tab){
    setSelected(id);setInitialTab(tab);changeRoute(id,tab);
  }
  async function create(event){
    event.preventDefault();
    if(creating)return;
    setCreating(true);setError('');
    try{
      const result=await api.call('project.create',{name:name.trim()||'Untitled project',format:'landscape',request_key:key});
      await loadProjects();setName('');setKey(requestKey());
      if(['music','stage'].includes(entry))location.assign(api.native(result.scene_id,entry));
      else selectScene(result.scene_id,entry);
    }catch(error){setError(error.message);}
    finally{setCreating(false);}
  }
  function updateScene(id,changes){
    setProjects(items=>items.map(item=>item.scene.id===id?{...item,scene:{...item.scene,...changes}}:item));
  }
  if(record)return <Workspace key={record.scene.id} {...{api,record,projects,selectScene,home,initialTab,updateScene,openCampaign,
    initialAsset:record.scene.id===route.scene?Number(new URLSearchParams(location.search).get('edit_asset'))||null:null}}/>;
  return <main className="ls-projects"><a href={home}>Exit Studio</a><h1>Lightek Studio</h1>
    {error&&<p role="alert" className="ls-error">{error}</p>}
    {load==='loading'?<p role="status">Opening your projects…</p>:load==='failed'?<button onClick={loadProjects}>Try again</button>:<>
      {selected&&!record&&<p role="status">The selected scene is unavailable. Choose a project below.</p>}
      <p>Edit your media, make music or animate a scene. AI generation is an optional workspace.</p>
      {api.dashboard&&<nav className="ls-row" aria-label="Start an editor"><a href={api.editor('photo')}>Photo &amp; graphics</a><a href={api.editor('video')}>Full video editor</a></nav>}
      <form onSubmit={create}><label>Project name (optional)<input value={name} maxLength="120" onChange={event=>{setKey(requestKey());setName(event.target.value);}}/></label><label>Start with<select value={entry} onChange={event=>setEntry(event.target.value)}><option value="timeline">Video editing</option><option value="music">Music &amp; audio</option><option value="stage">Animation &amp; characters</option><option value="create">AI generation</option></select></label><button className="ls-primary" disabled={creating}><Plus size={16}/> New project</button></form>
      <div className="ls-assets">{projects.map(item=>{
        const kind=item.scene.settings?.editor_kind;
        const content=<><strong>{item.project.name}</strong><small>{item.scene.name}</small></>;
        return api.dashboard&&['photo','video'].includes(kind)?<a key={item.scene.id} href={api.editor(kind,item.scene.id)}>{content}</a>:<button type="button" key={item.scene.id} onClick={()=>selectScene(item.scene.id,'timeline')}>{content}</button>;
      })}</div>
    </>}
  </main>;
}

function routeFrom(host,scene){
  const [,section,identifier,tab]=location.hash.split('/');
  return {scene:Number(scene)||Number(section==='studio'&&identifier)||Number(host?.dataset.sceneId)||null,
    tab:tab || (identifier==='library'?'library':host?.dataset.workspace)};
}

class StudioErrorBoundary extends React.Component {
  state = {failed:false};

  static getDerivedStateFromError() {
    return {failed:true};
  }

  render() {
    if (!this.state.failed) return this.props.children;

    const {api,home}=this.props;
    const scene=routeFrom().scene || this.props.route.scene;
    return <section className="ls-projects" aria-label="Lightek Studio recovery">
      <h1>Lightek Studio</h1>
      <p role="alert">Studio could not open this workspace.</p>
      <div className="ls-row">
        <button onClick={()=>location.reload()}>Reload Studio</button>
        {scene&&<a href={api.advanced(scene)}>Open advanced editor</a>}
        <a href={home}>Exit Studio</a>
      </div>
    </section>;
  }
}

function renderStudio(root,api,route,home) {
  root.render(<StudioErrorBoundary {...{api,route,home}}>
    <LightekUnifiedStudio {...{api,route,home}}/>
  </StudioErrorBoundary>);
}

const dashboardHost=document.querySelector('[data-unified-studio]');
if(dashboardHost){
  renderStudio(createRoot(dashboardHost),studioApi(dashboardHost),routeFrom(dashboardHost),dashboardHost.dataset.home);
}
let pwaHost,pwaRoot;
window.LightekUnifiedStudio={
  pwa(container,id){
    if(id&&!/^[1-9]\d*$/.test(id)&&id!=='library'&&id!=='create')return false;
    // Music, animation and the other native workspaces own their existing routes.
    // Returning false lets the PWA run the original Studio renderer and hooks.
    const requested=location.hash.split('/')[3];
    if(requested&&!workspaces.some(([name])=>name===requested)&&!Object.prototype.hasOwnProperty.call(aliases,requested))return false;
    if(requested==='stage')return false;
    if(pwaHost?.parentNode===container&&location.hash===activeHash)return true;
    if(pwaRoot)pwaRoot.unmount();
    pwaHost=document.createElement('div');
    container.replaceChildren(pwaHost);
    pwaRoot=createRoot(pwaHost);
    document.body.classList.add("lt-studio-unified");
    activeHash=location.hash;
    renderStudio(pwaRoot,studioApi(null),routeFrom(null,id),"#/home");
    return true;
  },
  leave(){document.body.classList.remove("lt-studio-unified");if(pwaRoot){pwaRoot.unmount();pwaRoot=null;pwaHost=null;}}
};
