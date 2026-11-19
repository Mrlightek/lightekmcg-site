import React,{useState} from 'react';
import {requestKey} from './api';

const controls=[['jaw_open','Jaw open'],['smile','Smile'],['blink','Blink'],['brow_raise','Brow raise'],
 ['mouth_wide','Mouth wide'],['mouth_round','Mouth round'],...['a','b','c','d','e','f','g','h','x'].map(key=>[`viseme_${key}`,`Speech shape ${key.toUpperCase()}`])];
const gestures=[['head','Head'],['left_arm','Left arm'],['right_arm','Right arm']];

function choices(objects,field){
 return objects.flatMap(({name,definition})=>(definition?.[field]||[])
  .filter(entry=>entry.name&&entry.name!=='Basis').map(entry=>[name,entry.name]));
}

export function CastImport({api,assets,busy,run,refresh}){
 const sources=assets.filter(asset=>asset.kind==='blend'&&asset.status==='ready'&&asset.native_url&&!asset.bundle_url&&!asset.metadata?.character_profile&&asset.metadata?.scenes?.length);
 const [sourceId,setSourceId]=useState(''),[sceneName,setSceneName]=useState(''),[name,setName]=useState('');
 const [bindings,setBindings]=useState({}),[bones,setBones]=useState({}),[key,setKey]=useState(requestKey),[result,setResult]=useState(null);
 const source=sources.find(asset=>String(asset.id)===sourceId);
 const scene=source?.metadata.scenes.find(row=>row.name===sceneName);
 const faces=choices(scene?.objects||[],'shape_keys'),rigBones=choices(scene?.objects||[],'bones');
 function changed(){setKey(requestKey());setResult(null);}
 function chooseSource(value){
  const asset=sources.find(item=>String(item.id)===value);
  setSourceId(value);setName(asset?.name||'');chooseScene(asset?.metadata.scenes[0]?.name||'');
 }
 function chooseScene(value){changed();setSceneName(value);setBindings({});setBones({});}
 function fields(controls,rows,values,setter,prefix){
  return controls.map(([id,label])=><label key={id}>{label}<select aria-label={`${prefix}: ${label}`} value={values[id]||''} onChange={event=>{changed();setter({...values,[id]:event.target.value});}}>
   <option value="">Choose {id==='jaw_open'?'a required control':'a control (optional)'}</option>
   {rows.map(([object,control],i)=><option key={i} value={i+1}>{object} · {control}</option>)}
  </select></label>);
 }
 function selected(values,rows,field){
  return Object.fromEntries(Object.entries(values).filter(([,index])=>index).map(([control,index])=>{
   const [object,key]=rows[Number(index)-1];
   return [control,{object,[field]:key}];
  }));
 }
 return <details className="ls-drawer"><summary>Bring in a Blender character</summary>
  <p>Import a packed .blend in Media Library, then bind its face controls here. Saved armature actions become available when you direct the Cast member.</p>
  {sources.length===0&&<p role="status">Import a Blender character and wait for media processing.</p>}
  {sources.length>0&&<fieldset disabled={busy}><legend>Register imported Cast</legend>
   <label>Blender character file<select value={sourceId} onChange={event=>chooseSource(event.target.value)}>
    <option value="">Choose a prepared Blender file</option>
    {sources.map(asset=><option key={asset.id} value={asset.id}>{asset.name}</option>)}
   </select></label>
   {source&&<>
    <label>Blender source scene<select value={sceneName} onChange={event=>chooseScene(event.target.value)}>
     {source.metadata.scenes.map(row=><option key={row.name}>{row.name}</option>)}
    </select></label>
    <label>Cast name<input value={name} maxLength={160} onChange={event=>{changed();setName(event.target.value);}}/></label>
    {faces.length===0?<p role="status">This scene needs a jaw-open shape key.</p>:<>
     {fields(controls.slice(0,1),faces,bindings,setBindings,'Face')}
     <details><summary>Optional face and gesture controls</summary>
      {fields(controls.slice(1),faces,bindings,setBindings,'Face')}
      {rigBones.length>0&&fields(gestures,rigBones,bones,setBones,'Bone')}
     </details>
    </>}
    <button type="button" disabled={!scene||!bindings.jaw_open||!name.trim()||!!result} onClick={()=>run(async()=>{
     const performer=await api.call('cast.register',{asset_id:source.id,name:name.trim(),request_key:key,profile:{source_scene:sceneName,
      bindings:selected(bindings,faces,'key'),bones:selected(bones,rigBones,'bone')}});
     setResult(performer);await refresh();
    })}>Save to Cast</button>
   </>}
  </fieldset>}
  {result&&<p role="status">{result.name} is ready. Choose it as a reusable performer.</p>}
 </details>;
}
