import React,{useEffect,useState} from 'react';
import {requestKey} from './api';
export function SequenceComposer(props){
 const [open,setOpen]=useState(false);
 return <details className="ls-drawer" aria-label="Performance sequence editor" onToggle={event=>setOpen(event.currentTarget.open)}><summary>Arrange performances into a sequence</summary>{open&&<SequenceEditor {...props}/>}</details>;
}
function SequenceEditor({api,scene,busy,run}){
 const [catalog,setCatalog]=useState([]),[shots,setShots]=useState([]),[name,setName]=useState('Scene sequence'),[receipt,setReceipt]=useState(null),[quote,setQuote]=useState(null),[sourceQuotes,setSourceQuotes]=useState({}),[key,setKey]=useState(requestKey),[error,setError]=useState(''),[ready,setReady]=useState(false),[reviewed,setReviewed]=useState(false);
 const active=['pending','running'].includes(receipt?.status);
 useEffect(()=>{let alive=true;
  Promise.all([api.call('sequence.catalog',{scene_id:scene.id}),api.call('sequence.status',{scene_id:scene.id})]).then(([choices,saved])=>{
   if(!alive)return;setCatalog(choices.performances);
   if(saved.status!=='idle'){setReceipt(saved);setName(saved.inputs.name);setShots(saved.inputs.shots);}
   else setShots(choices.performances.filter(row=>row.available).slice(0,2).map(row=>({operation_id:row.operation_id,in:0,out:row.seconds})));
  }).catch(cause=>{if(alive)setError(cause.message);}).finally(()=>{if(alive)setReady(true);});return()=>{alive=false;};
 },[api,scene.id]);
 useEffect(()=>{if(!active)return;let stopped=false,timer;const poll=async()=>{try{const saved=await api.call('sequence.status',{operation_id:receipt.operation_id});if(stopped)return;setReceipt(saved);setError('');if(['pending','running'].includes(saved.status))timer=setTimeout(poll,1500);}catch(cause){if(!stopped){setError(cause.message);timer=setTimeout(poll,3000);}}};timer=setTimeout(poll,1000);return()=>{stopped=true;clearTimeout(timer);};},[api,receipt?.operation_id,active]);
 useEffect(()=>{if(quote?.status!=='processing_sources'||!receipt?.operation_id)return;let stopped=false,timer;
  const poll=async()=>{try{const result=await api.call('sequence.quote',{operation_id:receipt.operation_id,reviewed:true});if(stopped)return;setQuote(result);if(result.status==='processing_sources')timer=setTimeout(poll,2500);}catch(cause){if(!stopped)setError(cause.message);}};
  timer=setTimeout(poll,2000);return()=>{stopped=true;clearTimeout(timer);};
 },[api,quote?.status,receipt?.operation_id]);
 function changed(){setKey(requestKey());setReceipt(null);setQuote(null);setSourceQuotes({});setReviewed(false);}
 function perform(action){run(async()=>{setError('');try{await action();}catch(cause){setError(cause.message);}});}
 function move(index,offset){changed();setShots(rows=>{const copy=rows.slice();[copy[index],copy[index+offset]]=[copy[index+offset],copy[index]];return copy;});}
 const available=catalog.filter(row=>row.available),seconds=shots.reduce((sum,row)=>sum+Number(row.out)-Number(row.in),0);
 const valid=shots.length>=2&&shots.length<=12&&seconds>0&&seconds<=30&&shots.every(row=>Number.isFinite(row.in)&&Number.isFinite(row.out)&&row.in>=0&&row.out-row.in>=1/12&&catalog.some(item=>item.operation_id===row.operation_id&&item.available&&row.out<=item.seconds));
 const money=quote=>new Intl.NumberFormat(undefined,{style:'currency',currency:quote.currency||'USD'}).format(quote.total_cents/100);
 return <section aria-label="Sequence cut">
  <p>Select reviewed performances from this project, put them in order and trim their edges. Named characters must reuse the same Cast identity across shots. The private review cut keeps their dialogue. Final delivery uses full source exports and the existing Timeline checkout.</p>
  <button type="button" disabled={busy||active} onClick={()=>perform(async()=>setCatalog((await api.call('sequence.catalog',{scene_id:scene.id})).performances))}>Refresh performances</button>
  {!available.length&&<p>Prepare and finish character performances in this project first, then reopen this panel.</p>}
  <label>Sequence name<input maxLength="120" disabled={active} value={name} onChange={event=>{changed();setName(event.target.value);}}/></label>
  {shots.map((shot,index)=><fieldset key={index} disabled={active}><legend>Sequence clip {index+1}</legend>
   <label>Clip {index+1} performance<select value={shot.operation_id} onChange={event=>{changed();const id=Number(event.target.value),row=catalog.find(item=>item.operation_id===id);setShots(rows=>rows.map((item,i)=>i===index?{operation_id:id,in:0,out:row.seconds}:item));}}>{catalog.map(row=><option key={row.operation_id} value={row.operation_id} disabled={!row.available}>{row.name}{!row.available?' · needs a fresh preview':''}</option>)}</select></label>
   <div className="ls-fields">{['in','out'].map(field=><label key={field}>Clip {index+1} {field} (seconds)<input type="number" step="0.083333" min="0" value={shot[field]} onChange={event=>{changed();const value=Number(event.target.value);setShots(rows=>rows.map((row,i)=>i===index?{...row,[field]:value}:row));}}/></label>)}</div>
   <div className="ls-row"><button type="button" disabled={index===0} onClick={()=>move(index,-1)}>Move clip {index+1} earlier</button><button type="button" disabled={index===shots.length-1} onClick={()=>move(index,1)}>Move clip {index+1} later</button><button type="button" onClick={()=>{changed();setShots(rows=>rows.filter((_,i)=>i!==index));}}>Remove clip {index+1}</button></div>
  </fieldset>)}
  <button type="button" disabled={active||!available.length||shots.length>=12} onClick={()=>{changed();const row=available[0];setShots(rows=>[...rows,{operation_id:row.operation_id,in:0,out:row.seconds}]);}}>Add sequence clip</button>
  <p>{Number.isFinite(seconds)?seconds.toFixed(2):'—'} seconds · 2–12 clips · up to 30 seconds per review cut</p>
  <button type="button" disabled={busy||active||!ready||!name.trim()||!valid} onClick={()=>perform(async()=>setReceipt(await api.call('sequence.prepare',{scene_id:scene.id,request_key:key,name:name.trim(),shots})))}>Preview sequence cut</button>
  {receipt&&<p role="status">Sequence {receipt.status}</p>}{receipt?.error&&<p role="alert">{receipt.error}</p>}
  {receipt?.status==='failed'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>setReceipt(await api.call('sequence.retry',{operation_id:receipt.operation_id})))}>Retry sequence preview</button>}
  {receipt?.url&&<video aria-label="Private sequence preview" controls playsInline src={receipt.url}/>}
  {receipt?.status==='completed'&&<><label><input type="checkbox" checked={reviewed} onChange={event=>setReviewed(event.target.checked)}/>I reviewed this sequence</label><button type="button" disabled={busy||!reviewed} onClick={()=>perform(async()=>setQuote(await api.call('sequence.quote',{operation_id:receipt.operation_id,reviewed:true})))}>Prepare sequence export</button></>}
  {quote?.status==='source_exports_required'&&<section aria-label="Required source exports"><p>Finish full exports of these performances, then choose Prepare sequence export again.</p>{quote.missing.map(row=><div key={row.operation_id}><span>{row.name}</span><button type="button" disabled={busy} onClick={()=>perform(async()=>{const value=await api.call('character.scene.quote',{operation_id:row.operation_id});setSourceQuotes(prior=>({...prior,[row.operation_id]:value}));})}>Price {row.name}</button>{sourceQuotes[row.operation_id]?.status==='awaiting_payment'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>location.assign((await api.call('render.checkout',{operation_id:sourceQuotes[row.operation_id].operation_id})).checkout_url))}>Export {row.name} · {money(sourceQuotes[row.operation_id].quote)}</button>}{sourceQuotes[row.operation_id]&&sourceQuotes[row.operation_id].status!=='awaiting_payment'&&<span>Full export {sourceQuotes[row.operation_id].status} · <a href={api.native(row.scene_id,api.dashboard?'deliver':'publish')}>Open delivery</a></span>}</div>)}</section>}
  {quote?.status==='processing_sources'&&<p role="status">Full source exports are being prepared for Timeline. The export price will appear when processing finishes.</p>}
  {quote?.edit_scene_id&&<a href={api.native(quote.edit_scene_id,'edit')}>Open editable sequence timeline</a>}
  {quote?.quote&&quote.status==='awaiting_payment'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>location.assign((await api.call('render.checkout',{operation_id:quote.operation_id})).checkout_url))}>Continue to sequence checkout · {money(quote.quote)}</button>}
  {quote?.status==='failed'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>setQuote(await api.call('sequence.quote',{operation_id:receipt.operation_id,reviewed:true})))}>Retry saved sequence export</button>}
  {quote?.operation_id&&quote.status!=='awaiting_payment'&&<p role="status">Full sequence export {quote.status}. Follow it in Social &amp; Publish.</p>}
  {error&&<p role="alert">{error}</p>}
 </section>;
}
