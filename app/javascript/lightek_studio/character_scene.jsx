import React,{useEffect,useState} from 'react';
import {requestKey} from './api';
import {ProductionTemplates} from './production_templates';
export function CharacterSceneComposer({api,scene,assets,busy,run,refresh,openTemplateScene}){
 const [name,setName]=useState('Sentinel'),[dialogue,setDialogue]=useState('We protect this city.');
 const [skin,setSkin]=useState('#925e43'),[wardrobe,setWardrobe]=useState('#344e78'),[hair,setHair]=useState('#211916');
 const [cast,setCast]=useState(''),[audio,setAudio]=useState(''),[voice,setVoice]=useState('en-us');
 const [catalog,setCatalog]=useState(null),[sceneTemplate,setSceneTemplate]=useState('studio'),[cameraMode,setCameraMode]=useState('character'),[gesture,setGesture]=useState('wave_right');
 const [restored,setRestored]=useState(false);
 const [key,setKey]=useState(requestKey),[receipt,setReceipt]=useState(null),[quote,setQuote]=useState(null),[error,setError]=useState('');
 const performers=assets.filter(asset=>asset.kind==='blend'&&asset.status==='ready'&&asset.metadata?.character_profile);
 const recordings=assets.filter(asset=>asset.kind==='audio'&&asset.status==='ready'&&Number(asset.metadata?.duration)>=.2&&Number(asset.metadata?.duration)<=2.8);
 const active=['pending','running'].includes(receipt?.status);
 useEffect(()=>{
  let alive=true;
  Promise.all([api.call('character.scene.catalog',{scene_id:scene.id}),api.call('character.scene.status',{scene_id:scene.id})]).then(([choices,result])=>{
   if(!alive)return;setCatalog(choices);
   if(result.status==='idle'){
    const key=choices.default_scene_template||'studio';setSceneTemplate(key);
    const defaults=choices.scene_templates.find(row=>row.key===key)?.defaults;
    if(defaults){setName(defaults.name);setDialogue(defaults.dialogue);setGesture(defaults.gesture);setCameraMode(defaults.camera_mode);if(defaults.cast_asset_id)setCast(String(defaults.cast_asset_id));}
    return;
   }
   setReceipt(result);
   const input=result.inputs;if(input){setName(input.name);setDialogue(input.dialogue);setVoice(input.voice);setSkin(input.colors.skin);setWardrobe(input.colors.wardrobe);setHair(input.colors.hair);setCast(input.cast_asset_id?String(input.cast_asset_id):'');setAudio(input.audio_asset_id?String(input.audio_asset_id):'');setSceneTemplate(input.scene_template||'studio');setCameraMode(input.camera_mode||'character');setGesture(input.gesture||'wave_right');}
  }).catch(cause=>{if(alive)setError(cause.message);}).finally(()=>{if(alive)setRestored(true);});return()=>{alive=false;};
 },[api,scene.id]);
 useEffect(()=>{
  if(!active)return;let stopped=false,timer;
  const poll=async()=>{
   try{const result=await api.call('character.scene.status',{operation_id:receipt.operation_id});if(stopped)return;setError('');setReceipt(result);if(['pending','running'].includes(result.status))timer=setTimeout(poll,2000);else await refresh();}
   catch(cause){if(!stopped){setError(cause.message);timer=setTimeout(poll,3000);}}
  };
  timer=setTimeout(poll,1000);return()=>{stopped=true;clearTimeout(timer);};
 },[api,receipt?.operation_id,active]);
 function change(setter,value){setter(value);setKey(requestKey());setQuote(null);setReceipt(null);}
 function perform(action){run(async()=>{setError('');try{await action();}catch(cause){setError(cause.message);}});}
 return <section aria-label="Performed character scene" className="ls-layered">
  <p>Create a three-second illustrated character study with spoken dialogue, timed mouth shapes, a starter action and selected camera coverage. Preparation creates an editable scene and reusable Cast asset.</p>
  <p className="ls-muted">The starter is a simple drawn puppet. This tests the production workflow; detailed character art and full-body action animation need further work.</p>
  <ProductionTemplates {...{api,scene,catalog,run,busy}} openScene={openTemplateScene}/>
  <label>Scene setup<select disabled={active||!catalog} value={sceneTemplate} onChange={event=>{
   const value=event.target.value;change(setSceneTemplate,value);const defaults=catalog.scene_templates.find(row=>row.key===value)?.defaults;
   if(defaults){setName(defaults.name);setDialogue(defaults.dialogue);setGesture(defaults.gesture);setCameraMode(defaults.camera_mode);setCast(defaults.cast_asset_id?String(defaults.cast_asset_id):'');}
  }}>{catalog?.scene_templates.map(row=><option key={row.key} value={row.key} disabled={!row.available}>{row.name}</option>)}</select></label>
  <p className="ls-muted">{catalog?.scene_templates.find(row=>row.key===sceneTemplate)?.description}</p>
  <div className="ls-fields"><label>Camera coverage<select disabled={active} value={cameraMode} onChange={event=>change(setCameraMode,event.target.value)}><option value="character">Frontal wide-to-close coverage</option><option value="template">Template cameras and cuts</option></select></label>
   <label>Starter action<select disabled={active} value={gesture} onChange={event=>change(setGesture,event.target.value)}><option value="wave_right">Wave right</option><option value="nod">Head nod</option><option value="shake">Head shake</option><option value="still">No added gesture</option></select></label></div>
  <label>Reusable performer<select disabled={active} value={cast} onChange={event=>change(setCast,event.target.value)}><option value="">Build an illustrated performer</option>{cast&&!performers.some(actor=>String(actor.id)===cast)&&<option value={cast}>Saved template performer</option>}{performers.map(actor=><option key={actor.id} value={actor.id}>{actor.name}</option>)}</select></label>
  <label>Character name<input disabled={active} maxLength="60" value={name} onChange={event=>change(setName,event.target.value)}/></label>
  {!cast&&<div className="ls-fields">{[['Skin',skin,setSkin],['Wardrobe',wardrobe,setWardrobe],['Hair',hair,setHair]].map(([label,value,setter])=><label key={label}>{label}<input disabled={active} type="color" value={value} onChange={event=>change(setter,event.target.value)}/></label>)}</div>}
  <label>Dialogue recording<select disabled={active} value={audio} onChange={event=>change(setAudio,event.target.value)}><option value="">Synthesize a stock voice from the line</option>{recordings.map(recording=><option key={recording.id} value={recording.id}>{recording.name}</option>)}</select></label>
  <p className="ls-muted">Prepared recordings must last 0.2–2.8 seconds. Import recordings in Media Library; longer performances remain available in the advanced Cast workspace.</p>
  <label>Spoken line<textarea disabled={active} maxLength="80" value={dialogue} onChange={event=>change(setDialogue,event.target.value)} placeholder="We protect this city."/></label>
  {!audio&&<label>Stock voice<select disabled={active} value={voice} onChange={event=>change(setVoice,event.target.value)}><option value="en-us">English · US</option><option value="en-gb">English · UK</option></select></label>}
  <button type="button" disabled={busy||active||!restored||!name.trim()||(!dialogue.trim()&&!audio)} onClick={()=>perform(async()=>{
   const result=await api.call('character.scene.prepare',{scene_id:scene.id,request_key:key,name:name.trim(),dialogue:dialogue.trim(),voice,skin,wardrobe,hair,scene_template:sceneTemplate,camera_mode:cameraMode,gesture,...(cast?{cast_asset_id:Number(cast)}:{}),...(audio?{audio_asset_id:Number(audio)}:{})});setReceipt(result);
  })}>Prepare performed short</button>
  {receipt&&<p role="status">{receipt.status} · {receipt.phase?.replaceAll('_',' ')}</p>}
  {receipt?.error&&<p role="alert">{receipt.error}</p>}
  {receipt?.status==='failed'&&<button type="button" disabled={busy} onClick={()=>perform(async()=>setReceipt(await api.call('character.scene.retry',{operation_id:receipt.operation_id})))}>Retry character preparation</button>}
  {receipt?.url&&<video aria-label="Performed character preview" src={receipt.url} controls playsInline preload="metadata"/>}
  {receipt?.status==='completed'&&<>
   <a href={api.native(receipt.scene_id,'performance')}>Open editable character scene</a>
   <button type="button" disabled={busy} onClick={()=>perform(async()=>setQuote(await api.call('character.scene.quote',{operation_id:receipt.operation_id})))}>Get performed shot export price</button>
  </>}
  {quote&&<div className="ls-row"><strong>{new Intl.NumberFormat(undefined,{style:'currency',currency:quote.quote.currency||'USD'}).format(quote.quote.total_cents/100)}</strong><button type="button" disabled={busy} onClick={()=>perform(async()=>location.assign((await api.call('render.checkout',{operation_id:quote.operation_id})).checkout_url))}>Continue to export checkout</button></div>}
  {error&&<p role="alert">{error}</p>}
 </section>;
}
