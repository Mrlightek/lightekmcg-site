import React, {useEffect, useState} from 'react';
import {Sparkles, Film, Sliders, Play, Plus, Image as ImageIcon, Video, UserCheck} from 'lucide-react';
import {pending, requestKey, waitFor} from './api';

export function Preview({asset, url, title = 'Studio Preview Monitor'}) {
  const src = url || asset?.proxy_url || asset?.preview_url;
  return <section className="ls-monitor" aria-label={title}>
    {src ? (asset?.kind === 'image' ? <img src={src} alt={asset.name || 'Generated image'}/> :
      asset?.kind === 'audio' ? <audio src={src} controls/> : <video src={src} controls playsInline preload="metadata"/>) :
      <div className="ls-placeholder"><Play size={30}/><strong>{title}</strong><p>Open a finished clip to preview it here.</p></div>}
  </section>;
}

const tools = [
  ['video',Video,'5s Video','Wan 2.2'],['image',ImageIcon,'Concept Art','SD 1.5'],
  ['character',UserCheck,'3D Actor','Blender + Rhubarb Lip Sync']
];

export function Creation({api, scene, assets, referenceAssets, inventory, jobs, selected, onSelect, add, refresh, timeline, go, run, busy, onRevision}) {
  const [mode,setMode]=useState('video');
  const [prompt,setPrompt]=useState('');
  const [seed,setSeed]=useState('');
  const [steps,setSteps]=useState('');
  const [model,setModel]=useState('');
  const [reference,setReference]=useState('');
  const [audio,setAudio]=useState('');
  const [actor,setActor]=useState('');
  const [preview,setPreview]=useState(null);
  const [phase,setPhase]=useState('');
  const [key,setKey]=useState(requestKey);
  const [abort]=useState(()=>new AbortController());
  useEffect(()=>()=>abort.abort(),[abort]);

  const actors=(scene.objects || []).filter(object=>object.definition?.character_profile);
  const voices=assets.filter(asset=>asset.status==='ready'&&(asset.kind==='audio'||asset.metadata?.has_audio));
  const pictures=referenceAssets;
  const recipeId=mode==='image'?'image':reference?'wan22_image_video':'wan22_video';
  const recipe=inventory?.recipes?.find(item=>item.id===recipeId);
  const models=(inventory?.models || []).filter(name=>/sd[-_. ]?1[-_. ]?5|v1[-_.]5/i.test(name));
  const currentModel=models.includes(model)?model:models[0];
  const currentAudio=voices.find(asset=>asset.id===Number(audio));
  const draft=jobs.find(job=>job.asset_id===selected);
  const asset=assets.find(row=>row.id===selected) || draft;
  const elapsed=Math.max(0,...timeline.clips.map(clip=>clip.start+(clip.out-clip.in)/(clip.speed||1)));

  function change(setter, value) {
    setter(value);
    setKey(requestKey());
  }

  async function generate() {
    if (mode !== 'character') {
      const result=await api.call('ai.generate',{
        scene_id:scene.id,recipe:recipeId,prompt:prompt.trim(),request_key:key,
        ...(seed!=='' ? {seed:Number(seed)} : {}), ...(steps!=='' ? {steps:Number(steps)} : {}),
        ...(mode==='image' ? {model:currentModel} : {}),
        ...(mode==='video'&&reference ? {input_asset_id:Number(reference)} : {})
      });
      setPreview(null);
      onSelect(result.asset_id);
      setKey(requestKey());
      await refresh();
      return;
    }
    const sourceOut=Math.min(30,Number(currentAudio.metadata.duration));
    const input={scene_id:scene.id,audio_asset_id:currentAudio.id,source_in:0,source_out:sourceOut};
    setPhase('Analyzing dialogue');
    try {
      const analysis=await api.call('performance.analyze',{...input,dialogue:prompt,request_key:key});
      const speech=await waitFor(()=>api.call('performance.analysis',{scene_id:scene.id,operation_id:analysis.id}),abort.signal);
      if(speech.status!=='completed')throw Error(speech.error || 'Speech analysis failed.');
      const take=await api.call('performance.save',{
        ...input,object_id:Number(actor),lock_version:scene.lock_version,start:0,
        lip_sync_mode:'phoneme',analysis_id:analysis.id,request_key:key+'-take'
      });
      onRevision(take.lock_version);
      setKey(requestKey());
      setPhase('Rendering character preview');
      const render=await api.call('performance.preview',{scene_id:scene.id});
      const result=await waitFor(()=>api.call('performance.preview',{scene_id:scene.id,operation_id:render.operation_id}),abort.signal);
      if(result.status!=='completed'||!result.url)throw Error(result.error || 'Character preview is unavailable.');
      setPreview(result.url);
    } finally { setPhase(''); }
  }

  return <div className="ls-create">
    <div className="ls-controls">
      <div className="ls-modes" aria-label="Production tool">
        {tools.map(([id,Icon,title,subtitle])=><button type="button" key={id} aria-pressed={mode===id} onClick={()=>{change(setMode,id);setSteps('');setPreview(null);}}><Icon size={18}/><strong>{title}</strong><small>{subtitle}</small></button>)}
      </div>
      <form onSubmit={event=>{event.preventDefault();run(generate);}}>
        {mode==='character' && <>
          <label>Character<select aria-label="Character" value={actor} onChange={event=>change(setActor,event.target.value)} required>
            <option value="">Choose a character in this scene</option>{actors.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}
          </select></label>
          {!actors.length && <a href={api.advanced(scene.id).replace('workspace=edit','workspace=cast')}>Set up a character rig</a>}
          <label>Voice recording<select aria-label="Voice recording" required value={audio} onChange={event=>change(setAudio,event.target.value)}>
            <option value="">Choose a recording</option>{voices.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}
          </select></label>
          <button type="button" onClick={()=>go('library')}>Upload a voice recording</button>
        </>}
        <label>{mode==='character'?'Dialogue transcript (optional)':'Describe your scene'}
          <textarea rows="4" required={mode!=='character'} maxLength={mode==='character'?4000:2000} value={prompt} onChange={event=>change(setPrompt,event.target.value)} placeholder={mode==='character'?'Paste the words spoken in the recording.':'Describe the subject, setting and action.'}/>
        </label>
        {mode==='video'&&<div className="ls-reference"><label>Starting frame (optional)<select value={reference} onChange={event=>change(setReference,event.target.value)}><option value="">Start from text</option>{pictures.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><button type="button" onClick={()=>go('library')}>Upload image</button></div>}
        {mode!=='character' && <details className="ls-drawer"><summary><Sliders size={16}/> Engine &amp; ComfyUI Parameters</summary><div>
          <p>{inventory?.connected?`Connected · ${inventory.device?.type || 'worker'}${inventory.device?.vram_free ? ` · ${(inventory.device.vram_free/1073741824).toFixed(1)} GB VRAM free` : ''}`:'Generation worker unavailable'}</p>
          {mode==='video'&&<p>Wan 2.2 · approximately 5 seconds</p>}
          <div className="ls-fields"><label>Seed<input type="number" min="0" max="4294967295" step="1" placeholder="Random" value={seed} onChange={event=>change(setSeed,event.target.value)}/></label>
          <label>Steps<input type="number" min="1" max="60" step="1" placeholder={recipe?.steps || 'Default'} value={steps} onChange={event=>change(setSteps,event.target.value)}/></label></div>
          {mode==='image'&&!models.length&&<p>No SD 1.5 checkpoint is installed on this worker.</p>}
          {mode==='image'&&!!models.length&&<label>Model<select value={currentModel || ''} onChange={event=>change(setModel,event.target.value)}>{models.map(name=><option key={name}>{name}</option>)}</select></label>}
          {api.dashboard&&<a href={api.advanced(scene.id).replace('workspace=edit','workspace=workflows')}>Manage generation worker</a>}
        </div></details>}
        {mode!=='character'&&!recipe?.ready&&<p className="ls-muted">{recipe?.reason || inventory?.reason || 'This workflow becomes available when its worker is ready.'}</p>}
        <button className="ls-primary" disabled={busy||(mode==='character'? !actor||!currentAudio||Number(currentAudio.metadata?.duration)<.1 : !prompt.trim()||!recipe?.ready||(mode==='image'&&!currentModel))}><Sparkles size={16}/>{phase || (mode==='character'?'Animate character':mode==='image'?'Generate concept art':'Generate 5s video')}</button>
      </form>
    </div>
    <div className="ls-screen">
      <Preview asset={mode==='character'?null:asset} url={preview}/>
      {preview && <button onClick={()=>go('publish')}>Render full scene</button>}
      {asset?.status==='ready'&&mode!=='character'&&<button onClick={()=>add(asset.id || asset.asset_id)}>Add to timeline</button>}
      <section className="ls-card"><div className="ls-row"><strong><Film size={16}/> Active Storyboard Sequence</strong><span>{elapsed.toFixed(1)}s</span><button onClick={()=>go('timeline')}>Open timeline</button></div>
        <div className="ls-strip">{timeline.clips.map((clip,index)=><button key={index} onClick={()=>onSelect(clip.asset_id)}>{assets.find(item=>item.id===clip.asset_id)?.name || `Clip ${index+1}`}</button>)}
          {!timeline.clips.length&&<p className="ls-muted">Add a finished clip to start the sequence.</p>}
        </div>
      </section>
      <section className="ls-card"><strong>Generation history</strong><div className="ls-strip">
        {jobs.map(job=><button key={job.asset_id} aria-pressed={selected===job.asset_id} onClick={()=>{onSelect(job.asset_id);setPreview(null);}}>{job.name}<small>{pending(job.status)?'In progress':job.status}{job.error?` · ${job.error}`:''}</small></button>)}
        {!jobs.length&&<p className="ls-muted">Generated clips and their progress appear here.</p>}
      </div></section>
    </div>
  </div>;
}
