import {AttentionFields,attentionAvailable} from './attention';
import React,{useEffect,useState} from 'react';
import {HairStyleField,PortraitField} from './performer_look';
import {requestKey} from './api';
import {ProductionTemplates} from './production_templates';
import {ActingFields,actingDefaults,actingAvailable} from './acting';
import {ContactFields,contactAvailable} from './contact';
const defaults=[{name:'Sentinel',voice:'en-us',skin:'#925e43',wardrobe:'#344e78',hair:'#211916',cast_asset_id:''},{name:'Beacon',voice:'en-gb',skin:'#b57955',wardrobe:'#945228',hair:'#211916',cast_asset_id:''}];
export function DialogueSceneComposer({api,scene,assets,busy,run,refresh,openTemplateScene,revision,onRevisionReady}){
 const [characters,setCharacters]=useState(defaults.map(row=>({...actingDefaults,...row}))),[turns,setTurns]=useState([{speaker:0,dialogue:'Stay alert.',audio_asset_id:''},{speaker:1,dialogue:'I am ready.',audio_asset_id:''}]);
 const [shotName,setShotName]=useState('');
 const [catalog,setCatalog]=useState(null),[template,setTemplate]=useState('studio'),[receipt,setReceipt]=useState(null),[quote,setQuote]=useState(null),[key,setKey]=useState(requestKey),[error,setError]=useState(''),[restored,setRestored]=useState(false);
 const handoff=template==='counter_handoff';
 const active=['pending','running'].includes(receipt?.status);
 useEffect(()=>{
  if(revision&&receipt?.status==='completed'&&receipt.operation_id)onRevisionReady?.(receipt);
 },[revision,receipt,onRevisionReady]);
 const performers=assets.filter(asset=>asset.kind==='blend'&&asset.status==='ready'&&asset.metadata?.character_profile);
 const recordings=assets.filter(asset=>asset.kind==='audio'&&asset.status==='ready'&&Number(asset.metadata?.duration)>=.2&&Number(asset.metadata?.duration)<=2.8);
 useEffect(()=>{let alive=true;
  Promise.all([api.call('character.scene.catalog',{scene_id:scene.id}),(revision?Promise.resolve(revision):api.call('character.scene.status',{scene_id:scene.id}))]).then(([choices,saved])=>{
   if(!alive)return;setCatalog(choices);setTemplate(choices.default_scene_template||'studio');
   if(saved.inputs?.mode==='dialogue'){
    if(!revision)setReceipt(saved);setShotName(saved.inputs.shot_name||'');setTemplate(saved.inputs.scene_template);
    setCharacters(saved.inputs.characters.map((row,index)=>({...actingDefaults,...row,...row.colors,portrait_asset_id:String(row.portrait_asset_id||''),...(saved.inputs.scene_template==='counter_handoff'?{contact:null}:{}),cast_asset_id:String((revision&&saved.cast_asset_ids?.[index])||row.cast_asset_id||'')})));
    setTurns(saved.inputs.turns.map(row=>({...row,audio_asset_id:row.audio_asset_id?String(row.audio_asset_id):''})));
   }
  }).catch(cause=>{if(alive)setError(cause.message);}).finally(()=>{if(alive)setRestored(true);});return()=>{alive=false;};
 },[api,scene.id,revision]);
 useEffect(()=>{if(!active)return;let stopped=false,timer;
  const poll=async()=>{try{const saved=await api.call('character.scene.status',{operation_id:receipt.operation_id});if(stopped)return;setReceipt(saved);setError('');if(['pending','running'].includes(saved.status))timer=setTimeout(poll,2000);else await refresh();}catch(cause){if(!stopped){setError(cause.message);timer=setTimeout(poll,3000);}}};
  timer=setTimeout(poll,1000);return()=>{stopped=true;clearTimeout(timer);};
 },[api,receipt?.operation_id,active]);
 function changed(){setKey(requestKey());setReceipt(null);setQuote(null);}
 function character(index,field,value){changed();setCharacters(rows=>rows.map((row,i)=>i===index?{...row,[field]:value}:row));}
 function turn(index,field,value){changed();setTurns(rows=>rows.map((row,i)=>i===index?{...row,[field]:value}:row));}
 function perform(action){run(async()=>{setError('');try{await action();}catch(cause){setError(cause.message);}});}
 const valid=characters.every((row,index)=>row.name.trim()&&(!handoff||!performers.some(actor=>String(actor.id)===row.cast_asset_id&&!actor.metadata.character_profile.reach_bindings?.[index===0?'right':'left']))&&attentionAvailable(row.attention,performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile,catalog?.scene_templates.find(item=>item.key===template)?.contact_targets||[],true)&&actingAvailable(row,performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile)&&contactAvailable(row.contact,performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile,catalog?.scene_templates.find(item=>item.key===template)?.contact_targets||[],row.entrance))&&new Set(turns.map(row=>row.speaker)).size===2&&turns.every(row=>row.dialogue.trim()||row.audio_asset_id);
 return <section className="ls-layered" aria-label="Two-character dialogue scene">
  <p>Stage two reusable characters with separate voices, timed mouth shapes and silent listening reactions. A two-shot opens the scene, then the camera follows each speaking turn.</p>
  <p className="ls-muted">Two to four turns; each recording lasts 0.2–2.8 seconds. Keep the complete conversation within eight seconds. CPU previews use simple illustrated performers and review quality.</p>
  <ProductionTemplates {...{api,scene,catalog,run,busy}} openScene={openTemplateScene}/>
  {revision&&!receipt&&<p role="status">Revising {revision.inputs.shot_name||'dialogue'}. Prepare a new take to keep the original in the sequence.</p>}
  <label>Shot name<input disabled={active} maxLength={120} value={shotName} onChange={event=>{changed();setShotName(event.target.value);}} placeholder="Opening exchange"/></label>
  <label>Dialogue scene setup<select disabled={active||!catalog} value={template} onChange={event=>{const setup=event.target.value;changed();setTemplate(setup);setCharacters(rows=>rows.map(row=>({...row,contact:null,attention:null,...(setup==='counter_handoff'?{body_action:'still',entrance:'none'}:{})})));}}>{catalog?.scene_templates.map(row=><option key={row.key} value={row.key} disabled={!row.available}>{row.name}</option>)}</select></label>
  {handoff&&<p>{characters[0].name||'Character 1'} passes the parcel to {characters[1].name||'Character 2'} while the dialogue plays. The counter supports the parcel.</p>}
  {characters.map((row,index)=><fieldset key={index} disabled={active}><legend>Character {index+1}</legend>
   <label>Character {index+1} name<input maxLength="60" value={row.name} onChange={event=>character(index,'name',event.target.value)}/></label>
   <label>Character {index+1} performer<select value={row.cast_asset_id} onChange={event=>character(index,'cast_asset_id',event.target.value)}><option value="">Build an illustrated performer</option>{row.cast_asset_id&&!performers.some(actor=>String(actor.id)===row.cast_asset_id)&&<option value={row.cast_asset_id}>Saved performer</option>}{performers.map(actor=><option key={actor.id} value={actor.id} disabled={handoff&&!actor.metadata.character_profile.reach_bindings?.[index===0?'right':'left']}>{actor.name}</option>)}</select></label>
   {handoff&&row.cast_asset_id&&performers.some(actor=>String(actor.id)===row.cast_asset_id&&!actor.metadata.character_profile.reach_bindings?.[index===0?'right':'left'])&&<p role="alert">This performer needs a bound {index===0?'right':'left'} hand for the handoff.</p>}
   {!row.cast_asset_id&&<div className="ls-fields">{['skin','wardrobe','hair'].map(field=><label key={field}>Character {index+1} {field}<input type="color" value={row[field]} onChange={event=>character(index,field,event.target.value)}/></label>)}</div>}
   {!row.cast_asset_id&&<HairStyleField label={`Character ${index+1} hairstyle`} value={row.hair_style} onChange={value=>character(index,'hair_style',value)} disabled={active}/>}
   {!row.cast_asset_id&&<PortraitField label={`Character ${index+1} portrait mask`} assets={assets} value={row.portrait_asset_id} onChange={value=>character(index,'portrait_asset_id',value)} disabled={active}/>}
   <ActingFields contactActive={handoff||!!row.contact} prefix={`Character ${index+1}`} value={row} onChange={(field,value)=>character(index,field,value)} disabled={active} mechanicsActive={handoff} profile={performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile}/>
   <AttentionFields prefix={`Character ${index+1}`} partner value={row.attention} onChange={value=>character(index,'attention',value)} targets={catalog?.scene_templates.find(item=>item.key===template)?.contact_targets||[]} profile={performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile} disabled={active}/>
   {!handoff&&<ContactFields prefix={`Character ${index+1}`} value={row.contact} onChange={value=>{changed();setCharacters(rows=>rows.map((item,i)=>i===index?{...item,contact:value,...(value?{body_action:'still'}:{})}:item));}} targets={catalog?.scene_templates.find(item=>item.key===template)?.contact_targets||[]} profile={performers.find(actor=>String(actor.id)===row.cast_asset_id)?.metadata?.character_profile} disabled={active} entrance={row.entrance}/>}
   <label>Character {index+1} stock voice<select value={row.voice} onChange={event=>character(index,'voice',event.target.value)}><option value="en-us">English · US</option><option value="en-gb">English · UK</option></select></label>
  </fieldset>)}
  {turns.map((row,index)=><fieldset key={index} disabled={active}><legend>Speaking turn {index+1}</legend>
   <label>Turn {index+1} speaker<select value={row.speaker} onChange={event=>turn(index,'speaker',Number(event.target.value))}>{characters.map((actor,i)=><option key={i} value={i}>{actor.name||`Character ${i+1}`}</option>)}</select></label>
   <label>Turn {index+1} line<textarea maxLength="80" value={row.dialogue} onChange={event=>turn(index,'dialogue',event.target.value)}/></label>
   <label>Turn {index+1} recording<select value={row.audio_asset_id} onChange={event=>turn(index,'audio_asset_id',event.target.value)}><option value="">Use this character's stock voice</option>{recordings.map(asset=><option key={asset.id} value={asset.id}>{asset.name}</option>)}</select></label>
   {turns.length>2&&<button type="button" onClick={()=>{changed();setTurns(rows=>rows.filter((_,i)=>i!==index));}}>Remove turn {index+1}</button>}
  </fieldset>)}
  <button type="button" disabled={active||turns.length>=4} onClick={()=>{changed();setTurns(rows=>[...rows,{speaker:rows[rows.length-1].speaker===0?1:0,dialogue:'',audio_asset_id:''}]);}}>Add speaking turn</button>
  <button type="button" disabled={busy||active||!restored||!valid} onClick={()=>perform(async()=>{
   const result=await api.call('character.scene.prepare',{scene_id:scene.id,request_key:key,mode:'dialogue',scene_template:template,...(shotName.trim()?{shot_name:shotName.trim()}:{}),
    characters:characters.map(({name,voice,skin,wardrobe,hair,hair_style,cast_asset_id,portrait_asset_id,emotion,body_action,entrance,contact,attention})=>({...((contact&&!handoff)?{contact}:{}),...(attention?{attention}:{}),emotion,body_action,entrance,name:name.trim(),voice,skin,wardrobe,hair,...(!cast_asset_id&&hair_style&&hair_style!=='curls'?{hair_style}:{}),...(cast_asset_id?{cast_asset_id:Number(cast_asset_id)}:portrait_asset_id?{portrait_asset_id:Number(portrait_asset_id)}:{})})),
    turns:turns.map(({speaker,dialogue,audio_asset_id})=>({speaker,dialogue:dialogue.trim(),...(audio_asset_id?{audio_asset_id:Number(audio_asset_id)}:{})}))});setReceipt(result);
  })}>Prepare dialogue scene</button>
  {receipt&&<p role="status">{receipt.status} · {receipt.phase?.replaceAll('_',' ')}</p>}
  {receipt?.error&&<p role="alert">{receipt.error}</p>}
  {receipt?.status==='failed'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>setReceipt(await api.call('character.scene.retry',{operation_id:receipt.operation_id})))}>Retry dialogue preparation</button>}
  {receipt?.url&&<video aria-label="Two-character dialogue preview" src={receipt.url} controls playsInline preload="metadata"/>}
  {receipt?.status==='completed'&&<>
   {receipt.cast_asset_ids?.length===2&&<button type="button" disabled={busy} onClick={()=>{changed();setCharacters(rows=>rows.map((row,index)=>({...row,cast_asset_id:String(receipt.cast_asset_ids[index])})));}}>Revise take with same cast</button>}
   <a href={api.native(receipt.scene_id,'performance')}>Open editable dialogue scene</a><button type="button" disabled={busy} onClick={()=>perform(async()=>setQuote(await api.call('character.scene.quote',{operation_id:receipt.operation_id})))}>Get dialogue export price</button></>}
  {quote&&<div className="ls-row"><strong>{new Intl.NumberFormat(undefined,{style:'currency',currency:quote.quote.currency||'USD'}).format(quote.quote.total_cents/100)}</strong><button type="button" disabled={busy} onClick={()=>perform(async()=>location.assign((await api.call('render.checkout',{operation_id:quote.operation_id})).checkout_url))}>Continue to dialogue checkout</button></div>}
  {error&&<p role="alert">{error}</p>}
 </section>;
}
