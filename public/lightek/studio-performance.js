/* Cast, facial bindings and saved performances over the native Blender engine. */
(() => {
  const ui=window.LightekStudioApp,esc=value=>E(String(value??''));
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const takeDrafts=new Map(),dirtyTakes=new Set();
  const state={assets:[],loaded:false,loading:false,error:'',source:0,sourceScene:'',speechRequest:null,selected:0,draftKey:'',draft:null,preview:null,speechTimer:null,timer:null,open:false,busy:false};
  const requestedMode=new URL(location.href).searchParams.get('workspace');
  if(['performance','3d','timeline','script','publish'].includes(requestedMode))ST.workspaceMode=requestedMode;
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const object=()=>current()?.scene.objects.find(o=>o.id===state.selected&&o.definition.character_profile)||current()?.scene.objects.find(o=>o.definition.character_profile);
  const field=(name,label,value='',type='text')=>`<label class="fld"><span>${esc(label)}</span><input name="${name}" type="${type}" ${type==='number'?'step="any"':''} value="${esc(value)}"></label>`;
  const options=(values,selected)=>values.map(([value,label])=>`<option value="${esc(value)}" ${String(value)===String(selected)?'selected':''}>${esc(label)}</option>`).join('');
  const run=async(fn)=>{if(state.busy||window.LightekStudioMotion?.busy())return;state.busy=true;try{await fn();}catch(error){toast(error.message);state.error=error.message;}finally{state.busy=false;if(state.open)render(1);}};
  async function load(before){
    if(state.loading)return;state.loading=true;
    try{const result=await call('assets.list',{surface:'performance',...(before?{before}:{})});state.assets=before?[...state.assets,...result.assets.filter(asset=>!state.assets.some(a=>a.id===asset.id))]:result.assets;state.nextBefore=result.next_before;state.loaded=true;state.error='';}
    catch(error){state.error=error.message;}
    finally{state.loading=false;capture();if(state.open)render(1);}
    clearTimeout(state.timer);
    if(state.open&&state.assets.some(a=>a.metadata?.performer_build&&a.status==='processing'))state.timer=setTimeout(()=>{if(state.open)load();},4000);
  }
  const previousStory=ui.story;
  STUDIO_WORKSPACE_MODES.push({key:'performance',label:'Cast & Performance',description:'Create a reusable performer, attach a recording and direct the take.'});
  ui.story=(record,mode)=>{
    state.open=mode==='performance';if(!state.open)return previousStory(record,mode);
    if(!state.loaded&&!state.loading)load();
    const actors=state.assets.filter(a=>a.metadata?.character_profile&&a.status==='ready');
    const sources=state.assets.filter(a=>a.kind==='blend'&&a.status==='ready'&&a.native_url);
    const source=sources.find(a=>a.id===state.source)||sources[0];
    const sourceScene=(source?.metadata.scenes||[]).find(s=>s.name===state.sourceScene)||source?.metadata.scenes?.[0];
    const faceOptions=[['','Unassigned'],...(sourceScene?.objects||[]).flatMap(o=>(o.definition.shape_keys||[]).filter(key=>key.name!=='Basis').map(key=>[JSON.stringify({object:o.name,key:key.name}),`${o.name} / ${key.name}`]))];
    const boneOptions=[['','Unassigned'],...(sourceScene?.objects||[]).flatMap(o=>(o.definition.bones||[]).map(bone=>[JSON.stringify({object:o.name,bone:bone.name}),`${o.name} / ${bone.name}`]))];
    const performer=object(),profile=performer?.definition.character_profile;
    const draftKey=`${record.scene.id}:${performer?.id}:${performer?.definition.performance?.take_id||''}`;
    if(draftKey!==state.draftKey){clearTimeout(state.speechTimer);state.speechTimer=null;if(state.draftKey)takeDrafts.set(state.draftKey,JSON.parse(JSON.stringify(state.draft)));state.draftKey=draftKey;state.draft=JSON.parse(JSON.stringify(takeDrafts.get(draftKey)||performer?.definition.performance||{audio_asset_id:0,source_in:0,duration:3,start:0,gain:1,expressions:[],gestures:[]}));state.preview=null;}
    const draft=state.draft;
    draft.lip_sync_mode ||= 'volume';draft.analysis_id ||= draft.lip_sync?.analysis_id;
    draft.mouth_cues ||= draft.lip_sync?.cues || [];draft.recognizer ||= draft.lip_sync?.recognizer || 'pocketSphinx';draft.dialogue ||= draft.lip_sync?.dialogue || '';
    if(['pending','running'].includes(draft.analysis_status)&&!state.speechTimer)state.speechTimer=setTimeout(()=>pollSpeech(draft.analysis_id,state.draftKey,draft.analysis_signature),1000);
    const audio=state.assets.filter(a=>a.status==='ready'&&(a.kind==='audio'||a.metadata.has_audio));
    if(!draft.audio_asset_id&&audio.length){draft.audio_asset_id=audio[0].id;draft.duration=Math.min(3,audio[0].metadata.duration||3);}
    const disabled=state.busy||window.LightekStudioMotion?.busy()?'disabled':'';
    return `<section class="studio-wave2 studio-performance"><span class="eb">LIGHTEK / CHARACTER DIRECTION</span><h2>Give your cast a performance.</h2><p>Create an editable toon performer or register your own packed Blender character. Recordings drive mouth movement; timed face and bone cues direct the performance.</p><div class="pwa-post-actions"><a class="btn" href="#/studio/library">Import character / dialogue / singing</a><button class="btn sm" data-a="studioCastRefresh">Refresh Cast</button>${state.nextBefore?'<button class="btn sm" data-a="studioCastMore">Load older assets</button>':''}</div>${state.error?`<p role="alert">${esc(state.error)}</p>`:''}<div class="g2"><section class="pwa-post"><h3>Your Cast</h3>${actors.map(actor=>`<article class="pwa-post"><h4>${esc(actor.name)}</h4>${actor.thumbnail_url?`<img class="pwa-media" src="${esc(actor.thumbnail_url)}" alt="${esc(actor.name)}">`:''}<p>${Object.keys(actor.metadata.character_profile.bindings).map(esc).join(' · ')}</p><button class="btn sm" data-a="studioCastPlace" data-id="${actor.id}" ${disabled}>Place in this scene</button></article>`).join('')||'<p>No saved performers yet.</p>'}${state.assets.filter(a=>a.metadata?.performer_build&&a.status!=='ready').map(a=>`<p role="status">${esc(a.name)} · ${esc(a.status)} ${esc(a.error||'')}${a.status==='failed'?`<button class="btn sm" data-a="studioCastRetry" data-id="${a.id}">Retry performer build</button>`:''}</p>`).join('')}<details open><summary>Create a Lightek toon performer</summary><form data-performance-form="create">${field('name','Character name','Lightek performer')}${field('skin','Skin','#925e43','color')}${field('wardrobe','Jacket','#64388b','color')}${field('hair','Hair','#211916','color')}<button class="btn p" ${disabled}>Build editable performer</button></form><p>This original toon rig is a working starter. You can also bring a detailed production character with compatible face controls.</p></details><details><summary>Register your Blender character</summary><form data-performance-form="register"><label class="fld"><span>Prepared native source</span><select name="asset_id" data-performance-source>${options(sources.map(a=>[a.id,a.name]),source?.id)}</select></label><label class="fld"><span>Source scene</span><select name="source_scene" data-performance-source-scene>${options((source?.metadata.scenes||[]).map(s=>[s.name,s.name]),sourceScene?.name)}</select></label>${field('name','Cast name',source?.name||'')}<h4>Facial bindings</h4>${['jaw_open','smile','blink','brow_raise','mouth_wide','mouth_round',...'abcdefghx'.split('').map(s=>'viseme_'+s)].map(control=>`<label class="fld"><span>${esc(control.replaceAll('_',' '))}${control==='jaw_open'?' · required':''}</span><select name="face_${control}">${options(faceOptions,'')}</select></label>`).join('')}<h4>Gesture bones · optional</h4>${['head','left_arm','right_arm'].map(control=>`<label class="fld"><span>${esc(control.replaceAll('_',' '))}</span><select name="bone_${control}">${options(boneOptions,'')}</select></label>`).join('')}<button class="btn p" ${disabled}>Save reusable character</button></form><p>Registration pins a source version. The original character stays available.</p></details></section><section class="pwa-post"><h3>Direct this take</h3>${performer?`<label class="fld"><span>Scene performer</span><select data-performance-performer>${options(record.scene.objects.filter(o=>o.definition.character_profile).map(o=>[o.id,o.name]),performer.id)}</select></label><form data-performance-form="take"><label class="fld"><span>Dialogue or singing recording</span><select name="audio_asset_id">${options(audio.map(a=>[a.id,a.name]),draft.audio_asset_id||audio[0]?.id)}</select></label><div class="pwa-editor-fields">${field('source_in','Source in · seconds',draft.source_in,'number')}${field('source_out','Source out · seconds',draft.source_in+draft.duration,'number')}${field('start','Scene start · seconds',draft.start,'number')}${field('gain','Voice gain',draft.gain,'number')}</div>${lipSyncPanel(draft,profile)}<h4>Face direction</h4>${draft.expressions.map((cue,i)=>`<div class="pwa-post"><select name="expression_${i}_control">${options(Object.keys(profile.bindings).map(c=>[c,c.replaceAll('_',' ')]),cue.control)}</select>${field(`expression_${i}_start`,'Start in take · seconds',cue.start,'number')}${field(`expression_${i}_end`,'End in take · seconds',cue.end,'number')}${field(`expression_${i}_value`,'Strength · 0–1',cue.value,'number')}<button type="button" class="btn sm" data-a="studioPerformanceCueRemove" data-kind="expressions" data-index="${i}">Remove cue</button></div>`).join('')}<button type="button" class="btn sm" data-a="studioPerformanceCueAdd" data-kind="expressions">Add face cue</button><h4>Gestures</h4>${draft.gestures.map((cue,i)=>`<div class="pwa-post"><select name="gesture_${i}_kind">${options([['nod','Nod'],['shake','Shake head'],['wave_left','Wave left'],['wave_right','Wave right']],cue.kind)}</select>${field(`gesture_${i}_start`,'Start in take · seconds',cue.start,'number')}${field(`gesture_${i}_end`,'End in take · seconds',cue.end,'number')}${field(`gesture_${i}_strength`,'Strength · 0–1',cue.strength,'number')}<button type="button" class="btn sm" data-a="studioPerformanceCueRemove" data-kind="gestures" data-index="${i}">Remove cue</button></div>`).join('')}<button type="button" class="btn sm" data-a="studioPerformanceCueAdd" data-kind="gestures">Add gesture</button><div class="pwa-post-actions"><button class="btn p" ${disabled}>Save performance</button><button type="button" class="btn sm" data-a="studioPerformanceRemove" ${disabled}>Remove saved take</button></div></form>${window.LightekStudioMotion?.view(record,performer)||''}<div class="pwa-post-actions"><button class="btn" data-a="studioPerformancePreview" ${disabled}>Preview saved take · up to 3 seconds</button><button class="btn p" data-a="studioPerformanceExport" ${disabled}>Export saved shot · quote</button></div>${state.preview?.url&&!state.preview.stale?`<video class="pwa-media" controls playsinline src="${esc(state.preview.url)}"></video>`:''}${state.preview?`<p role="status">Preview: ${esc(state.preview.status)} ${state.preview.stale?'· scene changed; save and request a new preview.':''} ${esc(state.preview.error||'')}</p>`:''}<p>Save before previewing. Full-shot exports include the recording and an editable Blender source. Use the existing 3D workspace to arrange your actor, set, lighting and cameras.</p>`:'<p>Place a Cast member in this scene to start directing.</p>'}</section></div></section>`;
  };
  window.LightekStudioPerformance={capture:()=>capture(),dirty:(sceneId=studioCurrentSceneId())=>!!window.LightekStudioMotion?.dirty(sceneId)||[...dirtyTakes].some(key=>key.startsWith(sceneId+':')),hasDrafts:()=>dirtyTakes.size>0||!!window.LightekStudioMotion?.hasDrafts(),leave:()=>{state.open=false;clearTimeout(state.timer);},busy:()=>state.busy||!!window.LightekStudioMotion?.busy()};
  app.addEventListener('input',event=>{if(event.target.closest('[data-performance-form="take"]'))dirtyTakes.add(state.draftKey);});
  function capture(){
    const form=app.querySelector('[data-performance-form="take"]');if(!form)return;
    const data=new FormData(form),draft=state.draft;
    draft.audio_asset_id=Number(data.get('audio_asset_id'));draft.source_in=Number(data.get('source_in'));draft.duration=Number(data.get('source_out'))-draft.source_in;draft.start=Number(data.get('start'));draft.gain=Number(data.get('gain'));
    draft.lip_sync_mode=data.get('lip_sync_mode')||'volume';draft.recognizer=data.get('recognizer')||'pocketSphinx';draft.dialogue=data.get('dialogue')||'';
    draft.mouth_cues=(draft.mouth_cues||[]).map((cue,i)=>({value:data.get(`mouth_${i}_value`)||cue.value,start:Number(data.get(`mouth_${i}_start`)??cue.start),end:Number(data.get(`mouth_${i}_end`)??cue.end)}));
    draft.expressions=draft.expressions.map((cue,i)=>({control:data.get(`expression_${i}_control`),start:Number(data.get(`expression_${i}_start`)),end:Number(data.get(`expression_${i}_end`)),value:Number(data.get(`expression_${i}_value`))}));
    draft.gestures=draft.gestures.map((cue,i)=>({kind:data.get(`gesture_${i}_kind`),start:Number(data.get(`gesture_${i}_start`)),end:Number(data.get(`gesture_${i}_end`)),strength:Number(data.get(`gesture_${i}_strength`))}));
  }
  const speechSignature=()=>JSON.stringify([state.draft.audio_asset_id,state.draft.source_in,state.draft.duration,state.draft.recognizer,state.draft.dialogue]);
  function lipSyncPanel(draft,profile){
    const shapes=[['A','A · closed / M B P'],['B','B · teeth / consonants'],['C','C · open / EH'],['D','D · wide open / AH'],['E','E · rounded / OH'],['F','F · puckered / OO'],['G','G · F V'],['H','H · L'],['X','X · rest']];
    return `<section class="studio-lipsync"><h4>Speech & mouth animation</h4><label class="fld"><span>Mouth movement</span><select name="lip_sync_mode">${options([['volume','Volume · dialogue or singing'],['phoneme','Speech · timed mouth shapes']],draft.lip_sync_mode)}</select></label>
      <p>Volume follows loudness. Speech analysis recognizes sounds and produces editable mouth shapes. Review timing against your recording.</p>
      <label class="fld"><span>Speech recognizer</span><select name="recognizer">${options([['pocketSphinx','English speech'],['phonetic','Phonetic · other languages']],draft.recognizer)}</select></label>
      <label class="fld"><span>Spoken dialogue · optional recognition guide</span><textarea name="dialogue" maxlength="4000">${esc(draft.dialogue||'')}</textarea></label>
      <button type="button" class="btn" data-a="studioSpeechAnalyze" ${state.busy||['pending','running'].includes(draft.analysis_status)?'disabled':''}>${['pending','running'].includes(draft.analysis_status)?'Analyzing recording…':'Analyze recording for lip sync'}</button>
      <p role="status">${esc(draft.analysis_status|| (draft.analysis_id?'Saved analysis available':'Choose the source in/out range, then analyze.'))}${draft.analysis_error?' · '+esc(draft.analysis_error):''}</p>
      <p>${Object.keys(profile.bindings).some(k=>k.startsWith('viseme_'))?'This character has dedicated mouth shapes.':'This character uses an approximation through its bound jaw, wide and round controls. Bind optional viseme shapes in Cast for more detail.'}</p>
      <details><summary>Mouth cue editor · ${(draft.mouth_cues||[]).length} cues</summary><p>Times are seconds from the source-in point. Cues must be ordered and cannot overlap; gaps use the rest shape.</p>
      <div class="studio-mouth-cues">${(draft.mouth_cues||[]).map((cue,i)=>`<div><label class="fld"><span>Shape ${i+1}</span><select name="mouth_${i}_value">${options(shapes,cue.value)}</select></label>${field(`mouth_${i}_start`,'Start',cue.start,'number')}${field(`mouth_${i}_end`,'End',cue.end,'number')}<button type="button" class="btn sm" data-a="studioMouthCueRemove" data-index="${i}">Remove</button></div>`).join('')}</div>
      <button type="button" class="btn sm" data-a="studioMouthCueAdd" ${(draft.mouth_cues||[]).length>=1024?'disabled':''}>Add mouth cue</button></details></section>`;
  }
  async function pollSpeech(id,key,signature){
    state.speechTimer=null;if(!state.open||state.draftKey!==key)return;
    try{
      const result=await call('performance.analysis',{scene_id:current().scene.id,operation_id:id});
      if(!state.open||state.draftKey!==key)return;capture();
      if(speechSignature()!==signature){state.draft.analysis_status='changed';state.draft.analysis_error='Recording, trim or dialogue changed. Analyze again.';render(1);return;}
      state.draft.analysis_status=result.status;state.draft.analysis_error=result.error||'';
      if(result.status==='completed'){state.draft.mouth_cues=result.result.cues;state.draft.lip_sync_mode='phoneme';dirtyTakes.add(key);render(1);}
      else if(['pending','running'].includes(result.status))state.speechTimer=setTimeout(()=>pollSpeech(id,key,signature),2000);
      else render(1);
    }catch(error){state.draft.analysis_status='failed';state.draft.analysis_error=error.message;if(state.open)render(1);}
  }
  A.studioSpeechAnalyze=()=>run(async()=>{
    capture();const key=state.draftKey,signature=speechSignature(),draft=state.draft,sceneId=current().scene.id;state.error='';
    const requestSignature=JSON.stringify([sceneId,signature]);if(state.speechRequest?.signature!==requestSignature)state.speechRequest={signature:requestSignature,key:crypto.randomUUID()};
    const result=await call('performance.analyze',{scene_id:current().scene.id,audio_asset_id:draft.audio_asset_id,source_in:draft.source_in,source_out:draft.source_in+draft.duration,recognizer:draft.recognizer,dialogue:draft.dialogue,request_key:state.speechRequest.key});
    state.speechRequest=null;draft.analysis_id=result.id;draft.analysis_status=result.status;draft.analysis_signature=signature;draft.analysis_error='';dirtyTakes.add(key);
    clearTimeout(state.speechTimer);state.speechTimer=setTimeout(()=>pollSpeech(result.id,key,signature),1000);
  });
  A.studioMouthCueRemove=button=>{capture();state.draft.mouth_cues.splice(Number(button.dataset.index),1);dirtyTakes.add(state.draftKey);render(1);};
  A.studioMouthCueAdd=()=>{capture();const cues=state.draft.mouth_cues,last=cues.at(-1)?.end||0;if(last>=state.draft.duration){toast('Shorten the last cue to make room.');return;}cues.push({value:'X',start:last,end:Math.min(last+.1,state.draft.duration)});dirtyTakes.add(state.draftKey);render(1);};
  A.studioCastRefresh=()=>load();A.studioCastMore=()=>load(state.nextBefore);
  A.studioCastRetry=button=>run(async()=>{await call('cast.retry',{asset_id:Number(button.dataset.id)});await load();toast('Performer retry queued.');});
  A.studioCastPlace=button=>run(async()=>{const scene=current().scene;const result=await call('cast.place',{scene_id:scene.id,lock_version:scene.lock_version,asset_id:Number(button.dataset.id),request_key:button.dataset.requestKey||=crypto.randomUUID()});state.selected=result.object_id;await A.studioLoad(true);toast('Character placed. Arrange it in the 3D workspace, then save a performance.');});
  A.studioPerformanceCueAdd=button=>{capture();dirtyTakes.add(state.draftKey);state.draft[button.dataset.kind].push(button.dataset.kind==='expressions'?{control:Object.keys(object().definition.character_profile.bindings).find(k=>k!=='jaw_open')||'jaw_open',start:0,end:Math.min(1,state.draft.duration),value:0.7}:{kind:'nod',start:0,end:Math.min(1,state.draft.duration),strength:0.5});render(1);};
  A.studioPerformanceCueRemove=button=>{capture();dirtyTakes.add(state.draftKey);state.draft[button.dataset.kind].splice(Number(button.dataset.index),1);render(1);};
  A.studioPerformanceRemove=()=>run(async()=>{const scene=current().scene;await call('performance.remove',{scene_id:scene.id,object_id:object().id,lock_version:scene.lock_version});dirtyTakes.delete(state.draftKey);await A.studioLoad(true);toast('Saved performance removed.');});
  A.studioPerformanceExport=()=>run(async()=>{const result=await call('render.quote',{scene_id:current().scene.id,output:'movie'});ui.setQuote(result);if(window.LightekStudioProduction)LightekStudioProduction.go('deliver',undefined,true);else{ST.workspaceMode='publish';render(1);}});
  async function poll(){
    if(!state.open||!state.preview||!['pending','running'].includes(state.preview.status))return;
    const sceneId=current().scene.id,operationId=state.preview.operation_id,draftKey=state.draftKey;
    try{const result=await call('performance.preview',{scene_id:sceneId,operation_id:operationId});if(!state.open||current()?.scene.id!==sceneId||state.draftKey!==draftKey)return;state.preview=result;if(state.open)render(1);if(['pending','running'].includes(state.preview.status))setTimeout(poll,3000);}catch(error){state.error=error.message;if(state.open)render(1);}
  }
  A.studioPerformancePreview=()=>run(async()=>{state.preview=await call('performance.preview',{scene_id:current().scene.id});setTimeout(poll,3000);});
  app.addEventListener('change',event=>{const el=event.target;if(el.hasAttribute('data-performance-source')){state.source=Number(el.value);state.sourceScene='';render(1);}if(el.hasAttribute('data-performance-source-scene')){state.sourceScene=el.value;render(1);}if(el.name==='audio_asset_id'&&el.closest('[data-performance-form="take"]')){capture();const audio=state.assets.find(a=>a.id===Number(el.value));state.draft.source_in=0;state.draft.duration=Math.min(30,audio?.metadata.duration||3);render(1);}if(el.hasAttribute('data-performance-performer')){state.selected=Number(el.value);render(1);}});
  app.addEventListener('submit',event=>{
    const form=event.target.closest('[data-performance-form]');if(!form)return;event.preventDefault();capture();
    const data=Object.fromEntries(new FormData(form));
    run(async()=>{
      if(form.dataset.performanceForm==='create'){await call('cast.create',{...data,request_key:form.dataset.requestKey||=crypto.randomUUID()});await load();toast('Performer build queued.');}
      if(form.dataset.performanceForm==='register'){
        const bindings={},bones={};for(const [key,value] of Object.entries(data)){if(key.startsWith('face_')&&value)bindings[key.slice(5)]=JSON.parse(value);if(key.startsWith('bone_')&&value)bones[key.slice(5)]=JSON.parse(value);}
        await call('cast.register',{name:data.name,asset_id:Number(data.asset_id),profile:{source_scene:data.source_scene,bindings,bones},request_key:form.dataset.requestKey||=crypto.randomUUID()});await load();toast('Character saved to Cast.');
      }
      if(form.dataset.performanceForm==='take'){
        const scene=current().scene;const {analysis_status,analysis_error,analysis_signature,...take}=state.draft;await call('performance.save',{scene_id:scene.id,object_id:object().id,lock_version:scene.lock_version,...take,source_out:state.draft.source_in+state.draft.duration,request_key:crypto.randomUUID()});state.preview=null;dirtyTakes.delete(state.draftKey);await A.studioLoad(true);toast('Performance saved. Render a preview to review it.');
      }
    });
  });
})();
