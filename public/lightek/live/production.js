/* Production-bound live setup. Loading only prepares the local program preview. */
(()=>{
 function boot(root,hooks){
  const q=selector=>root.querySelector(selector),host=q('[data-production-setup]');if(!host)return null;
  const scene=q('[data-production-scene]'),notice=q('[data-production-status]');let saved=null,pending=false;
  const buttons=()=>{q('[data-production-read]').disabled=pending||!scene.value;q('[data-production-save]').disabled=pending||!saved||String(saved.scene_id)!==scene.value;q('[data-production-apply]').disabled=pending||!saved?.preset||String(saved.scene_id)!==scene.value;scene.disabled=pending;hooks.updated();};
  const field=(selector,value)=>{const el=q(selector);if(!el)throw Error('Reopen Live Studio after deployment.');if(el.type==='checkbox')el.checked=!!value;else el.value=String(value??'');};
  const value=selector=>q(selector).value,checked=selector=>q(selector).checked;
  const request=async(method,body)=>{const response=await fetch(host.dataset.productionUrl+(method==='GET'?'&scene_id='+encodeURIComponent(scene.value):''),{method,credentials:'same-origin',headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]')?.content||''},...(body?{body:JSON.stringify(body)}:{})});const data=await response.json();if(!response.ok)throw Error(data.error||'Production setup is unavailable.');return data;};
  function checkPrepared(data) {
   if (host.dataset.preparedScene && String(data.scene_id) === host.dataset.preparedScene && String(data.lock_version) !== host.dataset.preparedRevision) {
    throw Error('The prepared scene changed. Ask Nevaeh to prepare the show again.');
   }
  }
  async function run(task){if(pending)return;pending=true;buttons();try{await task();}catch(error){notice.textContent=error.message;}finally{pending=false;buttons();}}
  const read=()=>run(async()=>{saved=null;const id=scene.value;if(!id)throw Error('Choose a production.');const data=await request('GET');if(id!==scene.value)return;checkPrepared(data);saved=data;notice.textContent=data.preset?'Saved production setup found. Load it into preview when ready.':'No saved setup yet. Choose your stage/media controls, then save them to this production.';});
  function capture(){const subject={};for(const key of ['source','color','threshold','x','depth','z','height'])subject[key]=['source','color'].includes(key)?value(key==='source'?'[data-stage-subject-source]':'[data-stage-'+key+']'):Number(value(key==='source'?'[data-stage-subject-source]':'[data-stage-'+key+']'));subject.enabled=checked('[data-stage-subject]');subject.key=checked('[data-stage-key]');const presentation=hooks.capturePresentation?.(),overlay=hooks.captureOverlay?.();return {version:overlay?3:presentation?2:1,...(overlay?{overlay}:{}),...(presentation?{presentation}:{}),layout:value('[data-layout]'),stage_asset_id:value('[data-stage-asset]')||null,visual_asset_id:value('[data-library-visual]')||null,overlay_asset_id:value('[data-library-overlay]')||null,audio_asset_id:value('[data-library-audio]')||null,loop:checked('[data-library-loop]'),volume:Number(value('[data-library-volume]')),camera:value('[data-stage-camera]'),subject};}
  const save=()=>run(async()=>{if(!saved||String(saved.scene_id)!==scene.value)throw Error('Check the saved setup before saving.');saved=await request('POST',{scene_id:saved.scene_id,lock_version:saved.lock_version,preset:capture()});notice.textContent='Live setup saved to this production. Show templates carry it into independent episodes.';});
  const apply=()=>run(async()=>{
   if(hooks.active())throw Error('Stop the broadcast before loading a production setup.');if(!saved?.preset||String(saved.scene_id)!==scene.value)throw Error('Check this production’s saved setup first.');
   const generation=hooks.generation();
   // Resolve references again before applying: stale or newly restricted assets must fail closed.
   const latest=await request('GET');checkPrepared(latest);if(generation!==hooks.generation())throw Error('Capture was released. Load the setup again when ready.');saved=latest;if(!latest.preset)throw Error('This production no longer has a saved setup.');const config=latest.preset;if(config.version===3&&!hooks.applyOverlay)throw Error('Reopen Live Studio to load graphic placement.');
   for(const [key,selector] of Object.entries({stage_asset_id:'[data-stage-asset]',visual_asset_id:'[data-library-visual]',overlay_asset_id:'[data-library-overlay]',audio_asset_id:'[data-library-audio]'})){
    const select=q(selector),id=config[key],asset=latest.assets.find(a=>a.id===id);
    if(id&&!asset)throw Error('A production asset is no longer available.');
    if(asset){let option=[...select.options].find(o=>o.value===String(id));if(!option){option=new Option(asset.name,String(id));select.add(option);}option.dataset.kind=asset.kind;option.dataset[key==='stage_asset_id'?'stageUrl':'libraryUrl']=asset.url;}
    field(selector,id||'');
   }
   hooks.applyOverlay?.(config.overlay||{});
   field('[data-library-loop]',config.loop);field('[data-library-volume]',config.volume);
   const subject=config.subject;for(const key of ['source','color','threshold','x','depth','z','height'])field(key==='source'?'[data-stage-subject-source]':'[data-stage-'+key+']',subject[key]);field('[data-stage-subject]',subject.enabled);field('[data-stage-key]',subject.key);
   if(await hooks.loadLibrary()!==true||generation!==hooks.generation())throw Error('Production media did not finish loading. Review its preview before trying again.');
   if(config.stage_asset_id){if(await hooks.loadStage()!==true||generation!==hooks.generation())throw Error('The production stage did not finish loading.');field('[data-stage-camera]',config.camera);if(value('[data-stage-camera]')!==config.camera)throw Error('The saved stage camera is no longer available. Choose a camera and save the setup again.');q('[data-stage-camera]').dispatchEvent(new Event('change',{bubbles:true}));}
   if(config.presentation){if(!hooks.applyPresentation)throw Error('Reopen Live Studio to load show styling.');hooks.applyPresentation(config.presentation);}
   field('[data-layout]',config.layout);hooks.updated();notice.textContent='Production setup loaded into local preview. Review sources and sound before starting a broadcast.';
  });
  q('[data-production-read]').addEventListener('click',read);q('[data-production-save]').addEventListener('click',save);q('[data-production-apply]').addEventListener('click',apply);scene.addEventListener('change',()=>{saved=null;buttons();notice.textContent='Check the selected production’s saved setup.';});buttons();if(scene.value)read();return {busy:()=>pending};
 }
 window.LightekLiveProduction={boot};
})();
