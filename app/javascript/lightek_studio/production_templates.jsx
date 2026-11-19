import React,{useState} from 'react';
import {requestKey} from './api';
export function ProductionTemplates({api,scene,catalog,run,busy,openScene}){
 const [selected,setSelected]=useState(''),[name,setName]=useState(''),[key,setKey]=useState(requestKey),[result,setResult]=useState(null),[error,setError]=useState('');
 const productions=catalog?.production_templates||[],saved=catalog?.saved_templates||[];
 function choose(value){setSelected(value);setKey(requestKey());setResult(null);const record=value.startsWith('saved:')?saved.find(row=>String(row.id)===value.slice(6)):productions.find(row=>row.key===value.slice(11));setName(((record?.name||'Production')+' · Episode 1').slice(0,120));}
 function perform(action){run(async()=>{setError('');try{await action();}catch(cause){setError(cause.message);}});}
 return <details className="ls-drawer" aria-label="Production template launcher">
  <summary>Start a production or saved show</summary>
  <p>Create an editable project with the template's scenes and saved brief. Open one scene below, choose its performer and dialogue, then prepare a short preview.</p>
  <label>Production or show template<select value={selected} disabled={busy} onChange={event=>choose(event.target.value)}><option value="">Choose a template</option>
   <optgroup label="Production templates">{productions.map(row=><option key={row.key} value={'production:'+row.key}>{row.name} · {row.scene_count} scenes</option>)}</optgroup>
   <optgroup label="Your saved shows">{saved.map(row=><option key={row.id} value={'saved:'+row.id}>{row.name} · {row.scene_count} scenes</option>)}</optgroup>
  </select></label>
  <label>New production name<input maxLength="120" value={name} disabled={busy} onChange={event=>{setName(event.target.value);setKey(requestKey());setResult(null);}}/></label>
  <button type="button" disabled={busy||!selected||!name.trim()} onClick={()=>perform(async()=>{
   const saved=selected.startsWith('saved:');
   setResult(await api.call('character.template.use',{scene_id:scene.id,request_key:key,name:name.trim(),source:saved?'saved':'production',...(saved?{project_id:Number(selected.slice(6))}:{template_key:selected.slice(11)})}));
  })}>Create template production</button>
  {result&&<section aria-label="Prepared production scenes"><p role="status">{result.name} · {result.scenes.length} editable scenes prepared.</p>
   <div className="ls-row">{result.scenes.map(row=><button type="button" disabled={busy} key={row.id} onClick={()=>perform(()=>openScene(row.id))}>Open {row.name}</button>)}</div>
   <p className="ls-muted">These are staged scenes. Cast performances, full renders and episode assembly still need direction and review.</p>
  </section>}
  {error&&<p role="alert">{error}</p>}
 </details>;
}
