/* Dashboard delivery over the existing timeline, Dymond Bank and publication workers. */
(() => {
  if(!window.LightekStudioProduction)return;
  const ui=LightekStudioApp, prior=ui.delivery, priorQuote=ui.setQuote, states=new Map();
  const formats={landscape:{output:'video',width:1920,height:1080,fps:30},portrait:{output:'video',width:1080,height:1920,fps:30},square:{output:'video',width:1080,height:1080,fps:30},audio:{output:'audio',width:1920,height:1080,fps:30}};
  const names={landscape:'Landscape · website, YouTube & OTT',portrait:'Portrait · TikTok, Reels & Shorts',square:'Square · social & product features',audio:'Audio · voice, music & podcasts'};
  let working=false,timer=null;
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const call=async(action,payload)=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const fingerprint=()=>JSON.stringify(LightekStudioTimeline.get());
  const state=record=>{if(!states.has(record.scene.id))states.set(record.scene.id,{quote:null,signature:null,source:'edit',operations:[],publications:[],loaded:false,loading:false,error:'',sourceError:''});return states.get(record.scene.id);};
  const publicationUrl=id=>{const raw=document.querySelector('#lightek-studio-dashboard').dataset.pwaUrl;const url=new URL(raw||'/lightek/index.html',location.origin);if(!['http:','https:'].includes(url.protocol))throw Error('Invalid PWA URL');url.hash='/post/'+Number(id);return url.href;};
  const money=q=>new Intl.NumberFormat(undefined,{style:'currency',currency:q?.currency||'USD'}).format(Number(q?.total_cents||0)/100);
  function formatKey(t){return Object.keys(formats).find(k=>formats[k].output===t.output&&(t.output==='audio'||formats[k].width===t.width&&formats[k].height===t.height))||'custom';}
  const button=(action,label,attrs='')=>`<button type="button" class="vw-btn" data-delivery="${action}" ${attrs} ${working?'disabled':''}>${label}</button>`;
  function quoteCard(s){
    if(!s.quote)return '';
    const changed=s.source==='edit'&&s.signature!==fingerprint();
    return `<section class="delivery-quote"><h3>${s.source==='edit'?'Edit export':'Blender shot'} · quote #${Number(s.quote.operation_id)}</h3><p>${E(money(s.quote.quote))} · review the total before payment</p>${changed?'<p role="status">Your edit changed after this quote. Request an updated quote before continuing.</p>':button('checkout','Continue to payment',`data-operation="${Number(s.quote.operation_id)}"`)}<p class="vw-help">Payment uses the existing Dymond Bank checkout. Rendering starts after verified payment.</p></section>`;
  }
  ui.delivery=(record,mode)=>{
    if(!document.querySelector('#lightek-studio-dashboard'))return prior(record,mode);
    const s=state(record),t=LightekStudioTimeline.get()||{clips:[]},key=formatKey(t),ready=t.clips?.length>0;
    if(!s.loaded&&!s.loading)queueMicrotask(()=>load(record));
    return `<section class="studio-delivery"><header><span class="eb">LIGHTEK / DELIVER</span><h2>Finish your production.</h2><p>Export your assembled edit, review the master, then publish or download it for your connected business channels.</p></header><div class="delivery-grid"><section class="delivery-card"><h3>1 · Export this edit</h3><p>${E(record.scene.name)} · ${t.clips?.length||0} clips · ${Number(t.width)||1920} × ${Number(t.height)||1080} · ${Number(t.fps)||24} fps</p><label class="vw-field"><span>Production format</span><select aria-label="Delivery format" data-delivery-setting="format" ${working?'disabled':''}>${Object.entries(names).map(([k,n])=>`<option value="${k}" ${key===k?'selected':''}>${E(n)}</option>`).join('')}${key==='custom'?'<option selected value="custom">Custom size</option>':''}</select></label><label class="vw-field"><span>File quality</span><select aria-label="Delivery quality" data-delivery-setting="export_preset" ${working?'disabled':''}><option value="review" ${t.export_preset!=='master'?'selected':''}>Share · H.264 MP4 / 16-bit WAV</option><option value="master" ${t.export_preset==='master'?'selected':''}>Master · ProRes MOV / 24-bit WAV</option></select></label><label class="vw-field"><span>Frame rate</span><select aria-label="Delivery frame rate" data-delivery-setting="fps" ${working?'disabled':''}>${[24,25,30,48,50,60].map(v=>`<option ${v===(t.fps||24)?'selected':''}>${v}</option>`).join('')}</select></label><p class="vw-help">Format changes keep your clips and effects. Review framing and title positions in Edit before exporting. ${t.export_preset==='master'?'Use Share MP4 for OTT publication.':''}</p>${ready?button('quote-edit','Save edit & get export quote'):'<p>No clips yet. Import footage, audio or stills, then add them to the timeline.</p>'}<a class="vw-btn" href="#/studio/${record.scene.id}/edit">${ready?'Review edit':'Add media & edit'}</a><details class="delivery-advanced"><summary>Render a Blender shot instead</summary><p>Render this scene’s animation as a movie. Completed shots can be added to your edit.</p>${button('quote-shot','Get Blender movie quote')}</details>${s.sourceError?`<p role="alert">${E(s.sourceError)}</p>`:''}${quoteCard(s)}</section><section class="delivery-card"><div class="delivery-heading"><h3>2 · Review & publish</h3>${button('refresh',s.loading?'Checking…':'Refresh exports')}</div><p class="vw-help">Completed masters can be downloaded or published to Lightek/PWA feeds and OTT catalogs. Download an MP4 for manual social upload; external posting requires a working destination adapter.</p>${s.error?`<p role="alert">${E(s.error)}</p>`:''}<div data-delivery-operations>${operationRows(record,s)}</div></section></div><section class="delivery-card"><h3>3 · Release activity</h3>${s.publications.map(p=>`<article class="delivery-release"><strong>Release #${Number(p.id)}</strong><span>${E(p.status)}</span>${p.scheduled_at?`<time>${E(new Date(p.scheduled_at).toLocaleString())}</time>`:''}${p.error?`<p role="alert">${E(p.error)}</p>`:''}${p.post_id?`<a class="vw-btn" href="${E(publicationUrl(p.post_id))}" target="_blank" rel="noopener">View publication</a>`:''}</article>`).join('')||'<p>No releases yet. Choose Publish / schedule on a completed master.</p>'}</section></section>`;
  };
  function operationRows(record,s){return s.operations.filter(op=>op.scene_id===record.scene.id).map(op=>`<article class="delivery-operation"><div><strong>${op.type==='edit_media'?'Edit export':'Blender render'} #${Number(op.id)}</strong><span>${E(op.status)}${op.draft_preview?' · Draft preview':''}</span></div>${op.output?`<small>${E(op.output.output)} · ${Number(op.output.width)} × ${Number(op.output.height)} · ${Number(op.output.fps)} fps</small>`:''}${op.error?`<p role="alert">${E(op.error)}</p>`:''}${op.status==='awaiting_payment'&&op.quote?`<p>${E(money(op.quote))} · saved export snapshot</p>${button('checkout','Pay for this saved export',`data-operation="${Number(op.id)}"`)}`:''}${op.status==='completed'?op.artifacts.map(a=>`<div class="delivery-artifact"><a href="${E(a.url)}" target="_blank" rel="noopener">Download ${E(a.filename)}</a>${!op.draft_preview&&['video','image','audio','preview'].includes(a.kind)?`<button type="button" class="vw-btn" data-a="studioArtifactPublish" data-project="${record.project.id}" data-artifact="${a.id}">Publish / schedule</button><button type="button" class="vw-btn" data-a="studioArtifactReuse" data-project="${record.project.id}" data-artifact="${a.id}">Use in edit library</button>`:''}</div>`).join(''):''}</article>`).join('')||`<p>${s.loading?'Checking exports…':'No exports for this sequence yet.'}</p>`;}
  function active(record){return current()?.scene.id===record.scene.id&&LightekStudioProduction.mode()==='deliver';}
  async function load(record){
    const s=state(record);if(s.loading)return;s.loading=true;
    try{const r=await call('operations.list',{project_id:record.project.id});s.operations=r.operations||[];s.publications=r.publications||[];s.error='';s.loaded=true;}
    catch(e){s.error=e.message;s.loaded=true;}
    finally{s.loading=false;if(active(record)&&!working)render(1);}
    clearTimeout(timer);
    if(active(record)&&[...s.operations,...s.publications].some(o=>['pending','running','queued','publishing','draft'].includes(o.status)||(o.status==='scheduled'&&(!o.scheduled_at||Date.parse(o.scheduled_at)<=Date.now()))))timer=setTimeout(()=>{if(active(record))load(record);},6000);
  }
  const priorLoad=A.studioOperationsLoad;
  A.studioOperationsLoad=()=>current()&&LightekStudioProduction.mode()==='deliver'?load(current()):priorLoad();
  ui.setQuote=value=>{priorQuote(value);const record=current();if(record&&value){const s=state(record);s.quote=value;s.source=value.operation_type==='build_scene'?'shot':'edit';s.signature=fingerprint();}};
  async function execute(action,b){
    if(working)return;const record=current();if(!record)return;const s=state(record);working=true;s.sourceError='';b.disabled=true;
    try{
      if(action==='quote-edit'){
        await LightekStudioTimeline.save();
        const r=await call('timeline.quote',{scene_id:record.scene.id});s.quote=r;s.source='edit';s.signature=fingerprint();
      }else if(action==='quote-shot'){
        s.quote=await call('render.quote',{scene_id:record.scene.id,output:'movie'});s.source='shot';s.signature=null;
      }else if(action==='checkout'){
        const id=Number(b.dataset.operation);
        if(s.quote?.operation_id===id&&s.source==='edit'&&s.signature!==fingerprint())throw Error('Your edit changed. Request an updated export quote.');
        const result=await call('render.checkout',{operation_id:id});const url=new URL(result.checkout_url);
        if(url.protocol!=='https:'||url.hostname!=='checkout.stripe.com')throw Error('Invalid checkout URL');
        window.top.location.href=url.href;
      }
      s.loaded=false;
    }catch(e){s.sourceError=e.message;}
    finally{working=false;if(active(record))render(1);}
  }
  app.addEventListener('click',e=>{const b=e.target.closest('[data-delivery]');if(!b)return;e.preventDefault();if(b.dataset.delivery==='refresh'){if(!working)load(current());}else execute(b.dataset.delivery,b);});
  app.addEventListener('change',e=>{
    const el=e.target,key=el.dataset.deliverySetting;if(!key||working)return;
    const t=LightekStudioTimeline.get();if(!t)return;
    const changes=key==='format'?formats[el.value]:{[key]:key==='fps'?Number(el.value):el.value};if(!changes)return;
    LightekStudioTimeline.configure(changes);render(1);
  });
  window.addEventListener('hashchange',()=>clearTimeout(timer));
  window.LightekStudioDelivery={busy:()=>working};
})();
