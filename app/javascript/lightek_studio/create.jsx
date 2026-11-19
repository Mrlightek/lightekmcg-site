import React, {useEffect,useState} from 'react';
import {Sparkles, Film, Sliders, Play, Box, Image as ImageIcon, Video, UserCheck} from 'lucide-react';
import {LayeredComposer} from './layered';
import {CharacterSceneComposer} from './character_scene';
import {progressLabel, requestKey, uploadMessage, waitFor} from './api';

export function Preview({asset, url, title = 'Studio Preview Monitor'}) {
  const src = url || asset?.proxy_url || asset?.preview_url;
  return <section className="ls-monitor" aria-label={title}>
    {src ? (asset?.kind === 'image' ? <img src={src} alt={asset.name || 'Generated image'}/> :
      asset?.kind === 'audio' ? <audio src={src} controls/> : <video src={src} controls playsInline preload="metadata"/>) :
      <div className="ls-placeholder"><Play size={30}/><strong>{title}</strong><p>Open a finished clip to preview it here.</p></div>}
  </section>;
}

const tools = [
  ['workflow',Film,'2D Scene & Parallax','Lightek renderer'],['performed',UserCheck,'Performed Short','Character · voice · cuts'],
  ['video',Video,'5s AI Video','Wan 2.2'],['image',ImageIcon,'Concept Art','SD 1.5'],
  ['movie',Box,'3D Procedural Movie',''],['character',UserCheck,'Character Performance & Lip-Sync','']
];
const engines = [['musetalk','MuseTalk'],['liveportrait','LivePortrait'],['facefusion','FaceFusion']];
const presetOptions = [['cube','Cube'],['sphere','Sphere'],['cylinder','Cylinder']];
const movieDefaults = {scene_preset:'cube',camera:'angle',lighting:'soft',motion:'spin'};
const poolLabel = {standard:'Standard Studio Queue',local:'Local CPU Pool',remote:'Central Remote CPU Pool'};

function Options({label,value,onChange,options}) {
  return <label>{label}<select aria-label={label} value={value} onChange={event=>onChange(event.target.value)}>
    {options.map(([id,name])=><option key={id} value={id}>{name}</option>)}
  </select></label>;
}
function MediaPicker({title,items,value,onChange,upload,accept,empty='Choose from Media Library'}) {
  return <div className="ls-reference">
    <Options label={title} value={value} onChange={onChange} options={[[ '', value&&!items.some(item=>String(item.id)===value)?'Preparing your media…':empty ],...items.map(item=>[String(item.id),item.name])]}/>
    {upload&&<label className="ls-upload">Upload file<input type="file" accept={accept} aria-label={`Upload ${title.toLowerCase()}`} onChange={event=>{
      const file=event.target.files[0];event.target.value='';if(file)upload(file);
    }}/></label>}
  </div>;
}

export function Creation({api,project,scene,assets,referenceAssets,inventory,inventoryError,retryInventory,jobs,operations,selected,onSelect,add,refresh,timeline,go,run,busy,onRevision,onCompositionSaved,onMode,openTemplateScene,initialMode,operationId,setOperationId}) {
  const [mode,setMode]=useState(initialMode||'workflow');
  const [composition,setComposition]=useState(()=>scene.settings?.composition_2d||null);
  const [nativeReady,setNativeReady]=useState(false);
  const [blenderHandoff,setBlenderHandoff]=useState(false);
  const [prompt,setPrompt]=useState('');
  const [seed,setSeed]=useState('-1');
  const [steps,setSteps]=useState('');
  const [quality,setQuality]=useState('auto');
  const [aspect,setAspect]=useState('16:9');
  const [worker,setWorker]=useState('');
  const [reference,setReference]=useState('');
  const [source,setSource]=useState('');
  const [driver,setDriver]=useState('');
  const [chosenEngine,setEngine]=useState('');
  const engine=chosenEngine || inventory?.performances?.find(item=>item.configured)?.id || 'rhubarb';
  const [rigPreview,setRigPreview]=useState('');
  const [phase,setPhase]=useState('');
  const [signal,setSignal]=useState(null);
  useEffect(()=>{
    const controller=new AbortController();
    setSignal(controller.signal);
    return ()=>controller.abort();
  },[]);
  const rig=engine==='rhubarb';
  const [movie,setMovie]=useState(movieDefaults);
  const [route,setRoute]=useState('');
  const [key,setKey]=useState(requestKey);
  const [quote,setQuote]=useState(null);
  const [details,setDetails]=useState(null);
  const [receipts,setReceipts]=useState({});
  const [failure,setFailure]=useState(null);
  const [error,setError]=useState('');
  const neural=mode==='video'||mode==='image';
  const currentReference=referenceAssets.find(item=>item.id===Number(reference))?.id;
  const recipeId=mode==='image'?'image':reference?'wan22_image_video':'wan22_video';
  const recipe=inventory?.recipes?.find(item=>item.id===recipeId);
  const workers=(inventory?.genesis_workers || []).filter(item=>item[mode]);
  const chosenWorker=workers.find(item=>String(item.id)===worker) || workers[0];
  const tool=inventory?.performances?.find(item=>item.id===engine);
  const pools=inventory?.render_pools || [];
  const unavailableLabel=inventoryError?'Status unavailable':'Checking availability…';
  const chosenPool=pools.includes(route)?route:pools[0];
  const readyMedia=assets.filter(item=>item.status==='ready'&&item.proxy_url);
  const sources=rig?(scene.objects || []).filter(item=>item.definition?.character_profile):readyMedia.filter(item=>(tool?.source || []).includes(item.kind));
  const drivers=readyMedia.filter(item=>rig?item.kind==='audio'&&Number(item.metadata?.duration)>0:item.kind===tool?.driver);
  const audioDriver=rig||tool?.driver==='audio';
  const job=jobs.find(item=>item.asset_id===selected);
  const asset=assets.find(item=>item.id===selected) || job;
  const sceneOperations=operations.filter(item=>item.scene_id===scene.id&&(!item.draft_preview||item.procedural_preview||item.id===operationId)&&['build_scene','edit_media'].includes(item.type));
  const chosenOperation=sceneOperations.find(item=>item.id===operationId);
  const operationVideo=chosenOperation?.status==='completed'&&chosenOperation.artifacts?.find(item=>item.kind==='video');
  const progress=chosenOperation ? (chosenOperation.cpu_resumable?'Recoverable':progressLabel(chosenOperation.status)) : progressLabel(job?.status || asset?.status);
  const elapsed=Math.max(0,...timeline.clips.map(clip=>clip.start+(clip.out-clip.in)/(clip.speed||1)));

  function change(setter,value){
    setter(value);setKey(requestKey());setQuote(null);setError('');setFailure(null);
  }
  function submit(action, message=()=>'Studio could not complete this request.') {
    run(async()=>{
      setError('');
      try {await action();}
      catch(cause){if(cause.name!=='AbortError'){setError(cause.data?.suggestion||(mode==='workflow'?cause.message:message(cause)));setFailure({error:cause.message,suggestion:cause.data?.suggestion,receipt:cause.workItemId || cause.data?.work_item_id});}}
    });
  }
  function upload(setter,file) {
    submit(async()=>{
      const result=await api.upload(file,project.id);
      change(setter,String(result.asset_id));
      await refresh();
    },uploadMessage);
  }
  function chooseMode(id){
    change(setMode,id);onMode?.(id);setOperationId(null);setRigPreview('');
  }
  function movieInputs(){
    const {scene_preset,...procedural_script_params}=movie;
    return {scene_id:scene.id,scene_preset,procedural_script_params};
  }
  async function previewMovie(){
    const result=await api.call('blender.preview',{...movieInputs(),request_key:key+'-draft'});
    setQuote(null);setOperationId(result.operation_id);
    await refresh();
  }
  async function generate() {
    let receipt;
    const recordReceipt=value=>{receipt=value;};
    if(mode==='workflow'){
      let graph=composition;
      if(!graph){graph=(await api.call('workflow.plan',{scene_id:scene.id,prompt:prompt.trim()})).composition;setComposition(graph);}
      const result=await api.call('workflow.create',{scene_id:scene.id,composition:graph,request_key:key},recordReceipt);
      setOperationId(result.operation_id);await refresh();
    }else if(mode==='movie'){
      const result=await api.call('render.quote',{
        ...movieInputs(),routing_mode:chosenPool,request_key:key
      },recordReceipt);
      setQuote(result);setOperationId(result.operation_id);
      if(receipt)setReceipts(previous=>({...previous,['operation-'+result.operation_id]:receipt}));
    }else if(mode==='character'&&rig){
      const audio=drivers.find(item=>item.id===Number(driver));
      const input={scene_id:scene.id,audio_asset_id:audio.id,source_in:0,source_out:Math.min(30,Number(audio.metadata.duration))};
      setRigPreview('');setOperationId(null);setPhase('Processing on Worker');
      try {
        const analysis=await api.call('performance.analyze',{...input,request_key:key},recordReceipt);
        const speech=await waitFor(()=>api.call('performance.analysis',{scene_id:scene.id,operation_id:analysis.id}),signal);
        if(speech.status!=='completed')throw Error(speech.error || 'Speech analysis failed.');
        const take=await api.call('performance.save',{
          ...input,object_id:Number(source),lock_version:scene.lock_version,start:0,
          lip_sync_mode:'phoneme',analysis_id:analysis.id,request_key:key+'-take'
        });
        onRevision(take.lock_version);
        setKey(requestKey());
        const render=await api.call('performance.preview',{scene_id:scene.id});
        const result=await waitFor(()=>api.call('performance.preview',{scene_id:scene.id,operation_id:render.operation_id}),signal);
        if(result.status!=='completed'||!result.url)throw Error(result.error || 'Character preview is unavailable.');
        setRigPreview(result.url);
      } finally {setPhase('');}
    }else{
      const payload=mode==='character'?{recipe:engine,input_asset_id:Number(source),driver_asset_id:Number(driver)}:
        {recipe:recipeId,prompt:prompt.trim(),genesis_worker_id:chosenWorker.id,...(quality!=='auto'?{quality_profile:quality}:{}),
          ...(mode==='image'?{aspect_ratio:aspect}:{seed:seed===''?-1:Number(seed),...(steps!==''?{steps:Number(steps)}:{}),
            ...(currentReference?{input_asset_id:currentReference}:{})})};
      const result=await api.call('ai.generate',{...payload,scene_id:scene.id,request_key:key},recordReceipt);
      setOperationId(null);onSelect(result.asset_id);
      if(receipt)setReceipts(previous=>({...previous,['asset-'+result.asset_id]:receipt}));
    }
    setKey(requestKey());
    await refresh();
  }
  async function addRender(){
    const result=await api.call('artifact.reuse',{project_id:project.id,artifact_id:operationVideo.id});
    onSelect(result.asset_id);await refresh();go('library');
  }

  const canGenerate=mode==='workflow'?nativeReady&&(composition||prompt.trim()):neural?chosenWorker&&recipe?.ready&&prompt.trim()&&(!reference||mode==='image'||currentReference):
    (rig?signal:tool?.configured)&&sources.some(item=>item.id===Number(source))&&drivers.some(item=>item.id===Number(driver));

  return <div className="ls-create">
    <div className="ls-controls">
      <div className="ls-modes" aria-label="Production tool">
        {tools.map(([id,Icon,title,subtitle])=><button type="button" key={id} aria-pressed={mode===id} disabled={busy}
          onClick={()=>chooseMode(id)}><Icon size={18}/><strong>{title}</strong>{subtitle&&<small>{subtitle}</small>}</button>)}
      </div>
      {inventoryError&&!['workflow','performed'].includes(mode)&&<div className="ls-card">
        <p role="alert">Studio couldn’t check worker availability.</p>
        <button type="button" onClick={retryInventory}>Retry worker check</button>
      </div>}
      {mode==='performed'&&<CharacterSceneComposer {...{api,scene,assets,busy,run,refresh,openTemplateScene}}/>}
      <form hidden={mode==='performed'} onSubmit={event=>{event.preventDefault();submit(mode==='movie'?previewMovie:generate);}}>
        {mode==='workflow'&&<LayeredComposer {...{api,scene,assets,composition,prompt,run,busy}} onReady={setNativeReady}
          setPrompt={value=>{change(setPrompt,value);setComposition(null);}}
          update={value=>change(setComposition,value)} onSaved={onCompositionSaved}/>}
        {neural&&<>
          <label>Prompt<textarea rows="4" required maxLength="2000" value={prompt} onChange={event=>change(setPrompt,event.target.value)} placeholder="Describe your scene."/></label>
          {mode==='video'&&<MediaPicker title="Starting frame (optional)" items={referenceAssets} value={reference} onChange={value=>change(setReference,value)}
            upload={file=>upload(setReference,file)} accept="image/png,image/jpeg,image/webp,.heic,.heif,.avif"/>}
          {mode==='video'&&reference&&!currentReference&&<small role="status">Preparing the starting frame</small>}
          {mode==='image'&&<Options label="Aspect ratio" value={aspect} onChange={value=>change(setAspect,value)} options={['16:9','9:16','1:1'].map(id=>[id,id])}/>}
          <Options label="Genesis worker" value={chosenWorker?String(chosenWorker.id):''} onChange={value=>change(setWorker,value)}
            options={workers.length?workers.map(item=>[String(item.id),item.label]):[['',inventory?'No available worker':unavailableLabel]]}/>
          {<details className="ls-drawer"><summary><Sliders size={16}/> Advanced</summary><div className="ls-fields">
            <Options label="Quality" value={quality} onChange={value=>change(setQuality,value)}
              options={[[ 'auto','Auto' ],[ 'economy','Economy' ],[ 'quality','Quality' ]]}/>
            {mode==='video'&&<>
            <label>Seed<input type="number" min="-1" max="4294967295" step="1" value={seed} onChange={event=>change(setSeed,event.target.value)}/><small>−1 picks a seed automatically.</small></label>
            <label>Steps<input type="number" min="1" max="60" step="1" placeholder={recipe?.steps || 'Default'} value={steps} onChange={event=>change(setSteps,event.target.value)}/></label>
            </>}
          </div></details>}
          {(inventoryError||(inventory&&(!chosenWorker||!recipe?.ready)))&&<button type="button" disabled={busy} onClick={()=>chooseMode('movie')}>Try a 3D draft</button>}
          {inventory&&(!chosenWorker||!recipe?.ready)&&<div className="ls-card" role="status">
            <p>{!inventory.connected ? inventory.reason || 'Studio couldn’t reach the Genesis engine.' :
              !recipe?.ready ? recipe?.reason || 'This workflow isn’t installed on the Genesis worker.' :
              !inventory.device ? 'ComfyUI responded, but Studio could not read the worker device information.' :
              mode==='video'&&inventory.device.type!=='cuda' ? 'ComfyUI is connected, but this Wan workflow requires a CUDA worker. The connected worker reports a different device type.' :
              'ComfyUI is connected, but no compatible Genesis worker is available for this tool.'}</p>
            {inventory.reason_code&&<small>Connection check: {inventory.reason_code}</small>}
            <button type="button" disabled={busy} onClick={retryInventory}>Recheck ComfyUI connection</button>
          </div>}
        </>}
        {mode==='movie'&&<>
          <Options label="Scene preset" value={movie.scene_preset} onChange={value=>change(setMovie,{...movie,scene_preset:value})} options={presetOptions}/>
          <Options label="Camera" value={movie.camera} onChange={value=>change(setMovie,{...movie,camera:value})} options={[[ 'angle','Three-quarter' ],['front','Front'],['overhead','Overhead']]}/>
          <Options label="Lighting" value={movie.lighting} onChange={value=>change(setMovie,{...movie,lighting:value})} options={[[ 'soft','Soft' ],['bright','Bright'],['low','Low']]}/>
          <Options label="Animation" value={movie.motion} onChange={value=>change(setMovie,{...movie,motion:value})} options={[[ 'spin','Rotate' ],['slide','Slide'],['still','None']]}/>
          <p className="ls-muted">Make a short preview with these settings.</p>
        </>}
        {mode==='character'&&<>
          <Options label="Engine" value={engine} onChange={value=>{change(setEngine,value);setSource('');setDriver('');setRigPreview('');}} options={[...engines,['rhubarb','Rhubarb · Character rig']]}/>
          <MediaPicker title={rig?'Character rig':'Source face'} empty={rig?'Choose a character in this scene':undefined} items={sources} value={source} onChange={value=>change(setSource,value)}/>
          <MediaPicker title={audioDriver?'Driver audio':'Driving video'} items={drivers} value={driver}
            onChange={value=>change(setDriver,value)} upload={file=>upload(setDriver,file)} accept={audioDriver?'audio/*':'video/*'}/>
          {rig&&!sources.length&&<a href={api.advanced(scene.id,'cast')}>Add a character to this scene</a>}
          {inventory&&!rig&&!tool?.configured&&<p className="ls-muted">This engine needs a configured character-performance worker.</p>}
        </>}
        <button className="ls-primary" disabled={busy||(mode==='movie'?['pending','running'].includes(chosenOperation?.status):!canGenerate)}><Sparkles size={16}/>{mode==='movie'?'Render draft':mode==='workflow'?'Render 2D preview':'Generate'}</button>
      </form>
      {mode==='workflow'&&composition&&<label><input type="checkbox" checked={blenderHandoff} onChange={event=>change(setBlenderHandoff,event.target.checked)}/>Include editable Blender project with full export</label>}
      {mode==='workflow'&&composition&&<button type="button" disabled={busy||!nativeReady} onClick={()=>submit(async()=>{
        const result=await api.call('workflow.quote',{scene_id:scene.id,composition,blender_handoff:blenderHandoff,request_key:key+'-final'});setQuote(result);setOperationId(result.operation_id);await refresh();
      })}>Get 2D export price</button>}
      {mode==='movie'&&pools.length>0&&<details className="ls-drawer"><summary>Full render</summary>
        <div className="ls-fields">
          <Options label="Render pool" value={chosenPool} onChange={value=>change(setRoute,value)} options={pools.map(id=>[id,poolLabel[id]])}/>
          {chosenPool==='remote'&&<small>Supports procedural shapes, cameras, lights and motion.</small>}
          <button type="button" disabled={busy} onClick={()=>submit(generate)}>Get render price</button>
        </div>
      </details>}
      {quote&&['movie','workflow'].includes(mode)&&<div className="ls-row">
        <strong>{new Intl.NumberFormat(undefined,{style:'currency',currency:quote.quote.currency||'USD'}).format(quote.quote.total_cents/100)}</strong>
        <button disabled={busy} onClick={()=>submit(async()=>{location.assign((await api.call('render.checkout',{operation_id:quote.operation_id})).checkout_url);})}>Continue to payment</button>
      </div>}
      {error&&<p className="ls-error" role="alert">{error}</p>}
    </div>
    <div className="ls-screen">
      <Preview asset={chosenOperation||rigPreview?null:asset} url={operationVideo?.url || (mode==='character'&&rig?rigPreview:null)}/>
      {phase&&<span className="ls-progress" role="status">{phase}</span>}
      {rigPreview&&<span className="ls-progress" role="status">Preview ready</span>}
      {!phase&&!rigPreview&&progress&&<div className="ls-row">
        <span className="ls-progress" role="status">{progress}</span>
        <button onClick={()=>setDetails(chosenOperation?{operationId:chosenOperation.id,receipt:receipts['operation-'+chosenOperation.id],error:chosenOperation.error}:{assetId:selected,receipt:receipts['asset-'+selected],error:job?.error})}>Operation Details</button>
      </div>}
      {error&&<button onClick={()=>setDetails(failure)}>Operation Details</button>}
      {error&&neural&&failure?.suggestion?.quality_profile==='economy'&&<button type="button" onClick={()=>{
        if(failure.suggestion.steps)setSteps(String(failure.suggestion.steps));
        change(setQuality,'economy');
      }}>Use Economy settings</button>}
      {chosenOperation?.cpu_resumable&&<button disabled={busy} onClick={()=>submit(async()=>{await api.call('render.resume',{operation_id:chosenOperation.id});await refresh();})}>{chosenOperation.layered_scene?'Retry saved export':'Resume Render from Checkpoint'}</button>}
      {chosenOperation?.status==='completed'&&!chosenOperation.draft_preview&&chosenOperation.artifacts?.filter(item=>item.kind==='blend').map(item=><a key={item.id} href={item.url} download>Download Blender project</a>)}
      {operationVideo&&!chosenOperation.draft_preview&&<button disabled={busy} onClick={()=>submit(addRender)}>Save clip to Media Library</button>}
      {!api.dashboard&&operationVideo&&!chosenOperation.draft_preview&&<button onClick={()=>{
        onSelect('render-'+operationVideo.id);go('publish');
      }}>Prepare to publish</button>}
      {!api.dashboard&&!chosenOperation&&asset?.status==='ready'&&asset.kind==='video'&&<button onClick={()=>go('publish')}>Prepare to publish</button>}
      {!chosenOperation&&!rigPreview&&asset?.status==='ready'&&<button disabled={busy} onClick={()=>add(asset.id || asset.asset_id)}>Add to timeline</button>}
      <section className="ls-card"><div className="ls-row"><strong><Film size={16}/> Storyboard</strong><span>{elapsed.toFixed(1)}s</span><button onClick={()=>go('timeline')}>Open timeline</button></div>
        <div className="ls-strip">
          {sceneOperations.map(item=><button key={item.id} aria-pressed={item.id===operationId} onClick={()=>{setRigPreview('');setOperationId(item.id);}}>{item.layered_scene?'2D Scene':item.procedural_preview?'3D Draft':item.type==='build_scene'?'3D Movie':'Export'}<small>{item.cpu_resumable?'Recoverable':progressLabel(item.status)}</small></button>)}
          {jobs.map(item=><button key={item.asset_id} aria-pressed={!chosenOperation&&selected===item.asset_id} onClick={()=>{onSelect(item.asset_id);setRigPreview('');setOperationId(null);}}>{item.name}<small>{progressLabel(item.status)}</small></button>)}
          {!jobs.length&&!sceneOperations.length&&<p className="ls-muted">Your clips and renders will appear here.</p>}
        </div>
      </section>
      {details&&<div className="ls-modal-backdrop"><section role="dialog" aria-modal="true" aria-labelledby="ls-details-title" className="ls-card ls-dialog" onKeyDown={event=>{if(event.key==='Escape')setDetails(null);if(event.key==='Tab')event.preventDefault();}}>
        <h2 id="ls-details-title">Operation Details</h2>
        {details.operationId&&<p>Operation {details.operationId}</p>}{details.assetId&&<p>Asset {details.assetId}</p>}
        {details.receipt&&<p>Nevaeh receipt {details.receipt}</p>}
        {details.error&&<p>{details.error}</p>}
        <button autoFocus onClick={()=>setDetails(null)}>Close</button>
      </section></div>}
    </div>
  </div>;
}
