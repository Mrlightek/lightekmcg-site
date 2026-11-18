/* One scene, one stage. This view reuses the native viewport and saved media APIs. */
(() => {
  const esc=v=>E(String(v??'')).replaceAll("'",'&#39;'), call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const state={starter:null,starterKey:null,starterLoaded:false,starterLoading:false,starterTimer:null,advanced:new URL(location.href).searchParams.get('workspace')==='publish',tab:'characters',assets:[],presets:[],loaded:false,loading:false,busy:false,message:'',sceneId:null,clip:null,preview:null,poll:0,mode:'layout'};
  const animationStart=()=>{
    const root=document.querySelector('#lightek-studio-dashboard');
    return !root||(root.dataset.workspace==='stage'&&!root.dataset.sceneId);
  };
  const sceneUrl=(id,mode='')=>`#/studio/${id}${mode?'/'+mode:''}`;
  const pendingCharacters=new Map();
  const placementKey=(sceneId,assetId)=>sceneId+':'+assetId;
  const characterTemplates={
    host:{skin:'#925e43',wardrobe:'#64388b',hair:'#211916',hair_style:'curls'},
    explorer:{skin:'#70412f',wardrobe:'#326764',hair:'#1d1513',hair_style:'close'},
    performer:{skin:'#b98362',wardrobe:'#9b453b',hair:'#46302a',hair_style:'high_top'}
  };
  const current=()=>studioSceneRecord(studioCurrentSceneId()), selected=()=>current()?.scene.objects.find(o=>Number(o.id)===Number(ST.selectedObjectId));
  const timeline=()=>window.LightekStudioTimeline.get()||{clips:[],width:1280,height:720};
  const key=()=>crypto.randomUUID(), button=(action,label,extra='')=>`<button type="button" class="vw-btn${action==='play-scene'?' primary':''}" data-vw="${action}" ${extra}>${label}</button>`;
  const field=(name,label,value,type='number')=>`<label class="vw-field"><span>${label}</span><input name="${name}" type="${type}" ${type==='number'?'step="any"':''} value="${esc(value)}"></label>`;
  const enabled=()=>window.LightekStudioProduction?(!studioCurrentSceneId()||LightekStudioProduction.mode()==='stage'):!state.advanced;
  function notice(message){state.message=message;const el=app.querySelector('[data-vw-message]');if(el){el.hidden=!message;el.textContent=message;}}
  async function run(fn){if(state.busy)return;state.busy=true;notice('Working…');try{await fn();}catch(error){notice(error.message||'The action failed. Try again.');if(state.mode==='render'){state.preview={error:error.message};showStage();}}finally{state.busy=false;queueMicrotask(placeReadyCharacter);}}
  async function load(more=false){
    if(state.loading)return;state.loading=true;
    try{const result=await call('assets.list',{surface:'visual',...(more&&state.next?{before:state.next}:{})});state.assets=more?[...state.assets,...result.assets.filter(a=>!state.assets.some(b=>a.id===b.id))]:result.assets;window.LightekStudioTimeline.assets(state.assets);state.next=result.next_before;state.presets=result.media_presets||[];state.loaded=true;}
    catch(e){notice(e.message);}finally{state.loading=false;if(app.querySelector('.vw-home'))updateHomeSection('.vw-template-grid', productionTemplates());else refresh(true);}
    placeReadyCharacter();
    clearTimeout(state.assetTimer);
    if(location.hash.startsWith('#/studio')&&state.assets.some(a=>['uploaded','processing'].includes(a.status)||(a.metadata?.performer_build&&a.status==='ready'&&!a.metadata.character_profile)))state.assetTimer=setTimeout(()=>load(),4000);
  }
  function starterPanel(){
    const job=state.starter,labels={queued:'Waiting for the Studio worker',delayed:'The Studio worker has not started this import. Retry to submit the same scene again.',checking_worker:'Checking the character worker',importing_rain_v3:'Importing Rain and her rig',importing_snow_v4:'Importing Snow and his rig',building_scene:'Building your first shot',preparing_editor:'Preparing the editor',ready:'Your character scene is ready',failed:'Scene preparation failed'};
    return `<section class="vw-starter-cast"><h2>Start with real characters</h2><p>Try a ready-made scene with Rain and Snow, a camera, lights and movement you can edit.</p>${job?`<p role="status">${esc(labels[job.phase]||job.phase)}</p>${job.error?`<p role="alert">${esc(job.error)}</p>`:''}`:''}${!state.starterLoaded?'<button class="vw-btn" disabled>Checking starter scenes…</button>':job?.phase==='ready'?`<a class="vw-btn primary" href="#/studio/${job.scene_id}${window.LightekStudioProduction?'/stage':''}">Open character scene →</a>`:job&&job.status!=='failed'&&job.phase!=='delayed'?'<button class="vw-btn" disabled>Preparing your scene…</button>':button('starter-cast',job?'Retry starter scene':'Use Rain & Snow')}<small>Rain Rig / Snow Rig (CC) Blender Foundation · CC-BY 4.0</small></section>`;
  }
  async function starterPoll(){
    if(state.starterLoading)return;state.starterLoading=true;
    try{const result=await call('starter.scene.status',state.starter?{asset_id:state.starter.asset_id}:{});state.starter=result?.asset_id?result:null;state.starterLoaded=true;if(state.starter?.phase==='ready'&&!studioSceneRecord(state.starter.scene_id))await A.studioLoad(true);}
    catch(error){state.starterLoaded=true;notice(error.message);}
    finally{state.starterLoading=false;updateHomeSection('.vw-starter-cast',starterPanel());}
    clearTimeout(state.starterTimer);
    if(app.querySelector('.vw-home')&&state.starter&&state.starter.phase!=='ready'&&state.starter.status!=='failed')state.starterTimer=setTimeout(starterPoll,4000);
  }
  function assetsPanel(){
    const ready=state.assets.filter(a=>a.status==='ready'),items=ready.filter(a=>state.tab==='characters'?a.metadata?.character_profile:state.tab==='sets'?['blend','glb','gltf','model'].includes(a.kind)&&!a.metadata?.character_profile:['audio','video','image'].includes(a.kind));
    const building=state.assets.filter(asset=>asset.metadata?.performer_build&&(!asset.metadata.character_profile||asset.status!=='ready'));
    const buildStatus=building.map(asset=>(asset.status==='failed'||asset.metadata.performer_delayed)
      ? `<p role="status">${esc(asset.name)} ${asset.metadata.performer_delayed?'is still waiting for the Studio worker.':'could not be created.'} ${button('retry-character','Retry',`data-id="${asset.id}"`)}</p>`
      : `<p role="status">${asset.metadata.performer_phase==='queued'?'Waiting to create':'Creating'} ${esc(asset.name)}…</p>`).join('');
    return `<div class="vw-pane-head"><h2>Add to your scene</h2>${button('refresh','↻','aria-label="Refresh assets"')}</div><nav class="vw-categories" aria-label="Asset categories">${[['characters','Characters'],['sets','Sets & props'],['media','Media']].map(([id,label])=>`<button data-vw="tab" data-id="${id}" class="${state.tab===id?'on':''}" aria-pressed="${state.tab===id}">${label}</button>`).join('')}</nav><div class="vw-pane-content">${state.tab==='characters'?`${button('create-character','Use a template')} ${button('create-photo','Use a photo')}`:state.tab==='sets'?`<p>Build a simple set, or add an imported model.</p>${[['plane','Studio floor'],['env_memory_chamber','Room'],['env_rooftop','Rooftop']].map(([id,label])=>button('set',label,`data-id="${id}"`)).join('')}`:'<p>Add footage, images or sound to your edit.</p>'}<label class="vw-btn vw-add">Upload ${state.tab==='media'?'media':'a model or recording'}<input type="file" data-vw-upload hidden accept="audio/*,video/*,image/*,.blend,.glb,.gltf,.obj,.fbx"></label>${items.map(a=>`<div class="vw-asset-row"><button class="vw-asset" data-vw="add" data-id="${a.id}" draggable="true" aria-label="Add ${esc(a.name)}">${a.thumbnail_url?`<img src="${esc(a.thumbnail_url)}" alt="">`:`<span class="vw-asset-icon">${a.kind==='audio'?'♫':a.kind==='video'?'▶':a.kind==='image'?'▧':a.metadata?.character_profile?'♟':'◇'}</span>`}<span><b>${esc(a.name)}</b><small>${esc(a.metadata?.character_profile?'Character':a.kind==='blend'?'3D asset':a.kind)}${a.metadata?.duration?' · '+Number(a.metadata.duration).toFixed(1)+'s':''}</small></span><em>＋</em></button>${state.tab==='characters'&&a.metadata?.performer_build?button('customize-character','Customize',`data-id="${a.id}" aria-label="Customize ${esc(a.name)}"`):''}</div>`).join('')||`<p class="vw-empty">${state.loading?'Loading your assets…':'No saved items here yet.'}</p>`}${state.tab==='characters'?buildStatus:''}${state.assets.filter(a=>a.status!=='ready'&&!a.metadata?.performer_build).map(a=>`<p role="status">${esc(a.name)} · ${esc(a.status)}${a.error?' · '+esc(a.error):''}</p>`).join('')}${state.next?button('more','Load older assets'):''}</div><div class="vw-in-scene"><h3>In this scene</h3>${(current()?.scene.objects||[]).map(o=>`<button class="vw-object ${Number(ST.selectedObjectId)===Number(o.id)?'on':''}" data-vw="select" data-id="${o.id}"><span>${o.definition?.character_profile?'♟':o.object_type==='camera'?'▣':'◇'}</span><span>${esc(o.name)}</span></button>`).join('')}</div>`;
  }
  function inspector(){
    const t=timeline(),clip=state.clip===null?null:t.clips[state.clip];
    if(clip)return `<div class="vw-pane-head"><h2>Selected clip</h2></div><form class="vw-inspector" data-vw-form="clip"><h3>${esc(state.assets.find(a=>a.id===clip.asset_id)?.name||'Media clip')}</h3><p class="vw-kind">Drag the clip to move it in time.</p>${field('start','Start in edit · seconds',clip.start)}<div class="vw-row">${field('in','Source in',clip.in)}${field('out','Source out',clip.out)}</div>${field('gain','Volume · 1 = original',clip.gain??1)}${field('track','Track · 0–15',clip.track)}<button class="vw-btn primary">Save clip</button>${button('remove-clip','Remove clip')}</form>`;
    const o=selected();if(!o)return `<div class="vw-pane-head"><h2>Your scene</h2></div><div class="vw-inspector"><h3>Make it yours.</h3><p class="vw-help">Add a character, set or media from the left. Click an item on the stage to work with it.</p><p class="vw-help">Drag to orbit. Scroll to zoom. Select Move to position an object.</p>${button('preview','Render camera preview')}<p class="vw-help">The layout is interactive. A camera preview shows the rendered shot.</p></div>`;
    const p=o.definition?.performance,motions=o.definition?.character_profile?.motions||[],audio=state.assets.filter(a=>a.status==='ready'&&(a.kind==='audio'||a.metadata?.has_audio));
    const controls=window.LightekStudioApp.objectControls?.(o)||'';
    const motionChoices=motions.map(motion=>button('add-motion',esc(motion.name),`data-id="${esc(motion.id)}"`)).join('');
    return `<div class="vw-pane-head"><h2>Selected object</h2></div><div class="vw-inspector"><h3>${esc(o.name)}</h3><p class="vw-kind">${o.definition?.character_profile?'Character':esc(o.object_type)} · use Move, Rotate or Scale on the stage</p>${o.definition?.character_profile?`${motionChoices?`<section class="vw-character-actions"><h4>Actions</h4><div>${motionChoices}</div></section>`:''}<form data-vw-form="take"><label class="vw-field"><span>Voice or singing recording</span><select name="audio_asset_id"><option value="">Choose a recording</option>${audio.map(a=>`<option value="${a.id}" ${Number(p?.audio_asset_id)===Number(a.id)?'selected':''}>${esc(a.name)}</option>`).join('')}</select></label><label class="vw-btn vw-add">Upload a recording<input type="file" data-vw-upload hidden accept="audio/*,video/*"></label><details><summary>Take timing</summary>${field('source_in','Recording starts at · seconds',p?.source_in||0)}${field('duration','Take length · up to 30 seconds',p?.duration||3)}${field('start','Scene start · seconds',p?.start||0)}</details><button class="vw-btn primary">Save & watch take</button></form>`:''}<details><summary>Position</summary><form data-vw-form="transform"><div class="vw-row three">${['X','Y','Z'].map((label,i)=>field('p'+i,label,(o.definition?.location||[0,0,0])[i])).join('')}</div><button class="vw-btn">Save position</button></form></details>${controls?`<details><summary>Object settings</summary>${controls}</details>`:''}</div>`;
  }
  const clipLength=c=>(Number(c.out)-Number(c.in))/(Number(c.speed)||1);
  function duration(){return Math.max(10,...timeline().clips.map(c=>Number(c.start)+clipLength(c)),...(current()?.scene.objects||[]).map(o=>{const p=o.definition?.performance;return Math.max(p?Number(p.start)+Number(p.duration):0,...(o.definition?.motion_clips||[]).map(c=>Number(c.start)+Number(c.duration)));}));}
  function lanes(){const t=timeline(),total=duration(),voices=(current()?.scene.objects||[]).filter(o=>o.definition?.performance);const moving=(current()?.scene.objects||[]).filter(o=>o.definition?.motion_clips?.length);const tracks=[...new Set(t.clips.map(c=>c.track))].sort((a,b)=>a-b);
    const bar=(start,length,label,attrs,voice=false)=>`<button class="vw-clip ${voice?'voice':''}" style="left:${Math.max(0,start)/total*100}%;width:${Math.max(.5,length/total*100)}%" ${attrs}><span>${esc(label)}</span></button>`;
    return `<div class="vw-ruler"><span>Scene timeline</span><div>${Array.from({length:10},(_,i)=>`<i style="left:${i*10}%">${(i*total/10).toFixed(0)}s</i>`).join('')}</div></div>${voices.map(o=>{const p=o.definition.performance;return `<div class="vw-lane"><div class="vw-lane-label">${esc(o.name)} · voice</div><div class="vw-lane-track">${bar(p.start,p.duration,'Saved performance',`data-vw="select" data-id="${o.id}"`,true)}</div></div>`;}).join('')}${moving.map(o=>`<div class="vw-lane"><div class="vw-lane-label">${esc(o.name)} · actions</div><div class="vw-lane-track">${o.definition.motion_clips.map(clip=>bar(clip.start,clip.duration,o.definition.character_profile?.motions?.find(m=>m.id===clip.action_id)?.name||'Action',`data-vw="select" data-id="${o.id}"`)).join('')}</div></div>`).join('')}${tracks.map(track=>`<div class="vw-lane"><div class="vw-lane-label">${esc(t.tracks?.find(a=>a.id===track)?.name||'Media '+(Number(track)+1))}</div><div class="vw-lane-track">${t.clips.map((c,i)=>c.track===track?bar(c.start,clipLength(c),state.assets.find(a=>a.id===c.asset_id)?.name||'Media clip',`data-vw="clip" data-index="${i}" aria-pressed="${state.clip===i}"`):'').join('')}</div></div>`).join('')}${!voices.length&&!moving.length&&!tracks.length?'<p class="vw-empty-timeline">Add media from the left, or give a character a recording. Your clips appear here.</p>':''}`;
  }
  function refresh(preserve=false){if(!enabled())return;if(preserve&&window.LightekStudioForms?.composing()){LightekStudioForms.defer();return;}const editing=preserve?window.LightekStudioForms?.capture():null;const form=preserve?app.querySelector('[data-vw-inspector] form'):null,saved=form?{kind:form.dataset.vwForm,values:Object.fromEntries(new FormData(form))}:null;const left=app.querySelector('[data-vw-assets]'),right=app.querySelector('[data-vw-inspector]'),tracks=app.querySelector('[data-vw-lanes]');if(left)left.innerHTML=assetsPanel();if(right){right.innerHTML=inspector();if(saved){const restored=right.querySelector(`[data-vw-form="${saved.kind}"]`);if(restored)for(const [name,value] of Object.entries(saved.values)){const input=restored.elements.namedItem(name);if(input)input.value=value;}}}if(tracks)tracks.innerHTML=lanes();const range=app.querySelector('[data-vw-playhead]');if(range)range.max=duration();const guide=app.querySelector('[data-vw-guide]');if(guide&&current())guide.innerHTML=sceneGuide(current().scene);if(preserve)window.LightekStudioForms?.restore(editing);}
  function sceneGuide(scene){
    const cast=scene.objects.find(object=>object.definition?.character_profile);
    const hasAction=scene.objects.some(object=>object.definition?.motion_clips?.length||object.definition?.performance);
    if(!cast)return `<p>Who’s in your scene?</p><div>${button('create-character','Pick a character')} ${button('create-photo','Use a photo')}</div>`;
    if(!hasAction)return `<p>Give your character something to do.</p><div>${button('select','Choose an action',`data-id="${cast.id}"`)} ${button('tab','Choose a set','data-id="sets"')}</div>`;
    return `<p>Ready to watch your scene.</p><div>${button('play-scene','Play scene')} ${button('tab','Choose a set','data-id="sets"')}</div>`;
  }
  function view(record){if(!document.querySelector('#lightek-studio-dashboard'))document.body.classList.add('lt-visual');ST.workspaceMode='3d';if(state.sceneId!==record.scene.id){state.sceneId=record.scene.id;state.tab='characters';state.clip=null;state.preview=null;state.mode='layout';state.poll++;}if(!state.loaded&&!state.loading)load();return `<main class="visual-workbench" data-view="${state.mode}" data-vw-scene="${record.scene.id}"><header class="vw-top"><a href="#/studio" class="vw-brand">LIGHTEK STUDIO</a><div><h1>${esc(record.project.name)}</h1><small>${esc(record.scene.name)}</small></div><div class="vw-actions"><a class="vw-btn" href="#/studio/${record.scene.id}/music">Music</a>${button('save-template','Save show template')}${button('advanced','Advanced tools')}${button('preview','Camera preview')}${button('export','Export')}</div></header><div class="vw-message" data-vw-message role="status" ${state.message?'':'hidden'}>${esc(state.message)}</div><div class="vw-guide" data-vw-guide>${sceneGuide(record.scene)}</div><div class="vw-body"><div class="studio-work-grid"><aside data-vw-assets>${assetsPanel()}</aside><aside data-vw-inspector>${inspector()}</aside></div></div><div class="vw-transport">${button('play-scene','▶ Play scene')}${button('play','Play edit')}${button('export','Export')}${button('stop','Stop edit')}<span class="vw-time" data-vw-time>00:00.0</span><input aria-label="Edit playhead" type="range" min="0" max="${duration()}" step="0.04" value="0" data-vw-playhead><small>Draft previews show up to 3 seconds</small></div><details class="vw-timeline-drawer" ${state.mode==='edit'?'open':''}><summary>Timeline</summary><div class="vw-timeline" data-vw-lanes>${lanes()}</div></details></main>`;}
  function mountStage(viewport){if(!enabled()||!viewport.closest('.visual-workbench'))return;const overlays=document.createElement('div');overlays.innerHTML=`<div class="vw-stage-mode">${button('layout','Layout')}${button('edit','Media edit')}</div><div class="vw-media-stage"><canvas width="960" height="540" data-timeline-preview></canvas><span data-timeline-status role="status"></span></div><div class="vw-render-stage"></div>`;while(overlays.firstChild)viewport.append(overlays.firstChild);viewport.addEventListener('dragover',e=>{if(e.dataTransfer.types.includes('application/x-lightek-asset'))e.preventDefault();});viewport.addEventListener('drop',e=>{e.preventDefault();const id=Number(e.dataTransfer.getData('application/x-lightek-asset'));if(id)run(()=>addAsset(id));});showStage();}
  function showStage(){const workbench=app.querySelector('.visual-workbench[data-view]');if(workbench){
    workbench.dataset.view=state.mode;
    if(state.mode==='edit'){const drawer=workbench.querySelector('.vw-timeline-drawer');if(drawer)drawer.open=true;}
  }const media=app.querySelector('.vw-media-stage'),preview=app.querySelector('.vw-render-stage');if(media)media.dataset.visible=state.mode==='edit';if(preview){preview.dataset.visible=state.mode==='render';const p=state.preview;preview.innerHTML=p?.url&&!p.stale?`${p.video?`<video src="${esc(p.url)}" controls playsinline autoplay></video>`:`<img src="${esc(p.url)}" alt="Rendered camera preview">`}${button('layout','Back to layout')}`:`<div class="vw-render-progress">${p?.error?'':'<span class="vw-loader"></span>'}<strong>${esc(p?.error?'Preview failed':'Rendering your camera')}</strong><p>${esc(p?.error||p?.status||'Waiting for the render worker…')}</p>${button('layout','Back to layout')}</div>`;}}
  async function reload(){await A.studioLoad(true);const r=current();if(r)window.LightekStudioTimeline.set(r.scene.settings.timeline||{output:'video',width:1280,height:720,clips:[]});refresh();}
  function placeReadyCharacter(){
    if(state.busy||!enabled()||!app.querySelector('[data-vw-scene]'))return;
    const sceneId=current()?.scene.id;
    const queued=[...pendingCharacters.values()].find(entry=>entry.sceneId===sceneId&&!entry.attempted&&state.assets.some(asset=>asset.id===entry.assetId&&asset.status==='ready'&&asset.metadata?.character_profile));
    if(queued){queued.attempted=true;run(()=>addAsset(queued.assetId));}
  }
  async function addAsset(id){const a=state.assets.find(a=>a.id===id);if(!a||a.status!=='ready')throw Error('Wait for this asset to finish processing.');const scene=current().scene,media=['audio','image','video'].includes(a.kind);if(window.LightekStudioTimeline.dirty?.())await window.LightekStudioTimeline.save();const result=await call(a.metadata?.character_profile?'cast.place':media?'asset.use':'asset.place',{asset_id:id,scene_id:scene.id,lock_version:scene.lock_version,placement:'append',request_key:pendingCharacters.get(placementKey(scene.id,id))?.requestKey||key()});pendingCharacters.delete(placementKey(scene.id,id));if(result.object_id)ST.selectedObjectId=result.object_id;await reload();notice(media?'Added to the media edit. Press Play edit to watch it.':'Added to the stage. Select Move to position it.');if(media){state.mode='edit';showStage();}}
  async function preview(video=false,scenePlayback=false){const id=current().scene.id,token=++state.poll,frame=Number(current().scene.settings.frame_current||current().scene.settings.frame_start||1),action=video?'performance.preview':'blender.preview';window.LightekStudioTimeline.stop();state.mode='render';state.preview={status:'Queued'};showStage();notice('');let result=await call(action,{scene_id:id,frame,...(scenePlayback?{scene_playback:true}:{})});let attempts=0;while(token===state.poll&&current()?.scene.id===id){state.preview={...result,video};showStage();if(result.error||result.url||!['pending','running','queued'].includes(result.status))break;if(++attempts>=120){notice('Preview is still processing. You can return to layout and check it later.');break;}await new Promise(resolve=>setTimeout(resolve,2500));if(token!==state.poll||current()?.scene.id!==id)return;result=await call(action,{scene_id:id,frame,operation_id:result.operation_id});}if(token===state.poll&&!result.url&&!result.error&&!['pending','running','queued'].includes(result.status)){state.preview={error:'No preview was returned. Try playing the scene again.'};showStage();}if(result.stale)notice('The scene changed. Render a new preview.');}
  function dialog(html){
    const el=document.createElement('dialog');el.className='vw-dialog';el.innerHTML=html;
    el.addEventListener('close',()=>{if(el.photoUrl)URL.revokeObjectURL(el.photoUrl);el.remove();});
    app.append(el);el.showModal();return el;
  }
  async function uploadAsset(file){
    const body=new FormData();
    body.append('file',file);body.append('purpose','studio_asset');
    const response=await fetch(window.LightekStudioUploadUrl||'/api/lightek/pwa/uploads',{
      method:'POST',credentials:'same-origin',headers:nevaeh.csrfHeaders(),body
    });
    return nevaeh.parseResponse(response);
  }
  async function appendMotion(actionId, requestButton){
    const scene=current().scene,character=selected();
    const action=character?.definition.character_profile?.motions?.find(m=>m.id===actionId);
    if(!action)throw Error('Choose an action for the selected character.');
    if(window.LightekStudioMotion?.dirty(scene.id))throw Error('Save or reload your action edits in Cast before adding another.');
    const clips=character.definition.motion_clips||[];
    if(clips.length>=32)throw Error('This character already has 32 actions. Remove one in Cast to add another.');
    const start=clips.reduce((last,clip)=>Math.max(last,Number(clip.start)+Number(clip.duration)),0);
    const duration=(action.frame_end-action.frame_start)/action.fps;
    if(!Number.isFinite(duration)||duration<.05||duration>60||start+duration>600)throw Error('This action does not fit in the scene. Adjust its timing in Cast.');
    const revision=character.definition.motion_revision||0;
    const signature=JSON.stringify([scene.id,character.id,revision,actionId]);
    if(requestButton.motionRequest?.signature!==signature)requestButton.motionRequest={signature,id:key()};
    const id=requestButton.motionRequest.id;
    await call('motion.save',{
      scene_id:scene.id,object_id:character.id,lock_version:scene.lock_version,motion_revision:revision,
      request_key:id,clips:[...clips,{id,action_id:action.id,source_in:action.frame_start,source_out:action.frame_end,start}]
    });
    await reload();
    notice(`${action.name} added. Press Play scene to watch.`);
  }
  function characterEditor(asset,photoMode=false){
    const hasPhoto=!!asset?.metadata?.photo_character;
    const photoOption=hasPhoto?'Replace photo':'Use a photo';
    const draft={...characterTemplates.host,...asset?.metadata?.performer_build};
    const presets=asset||photoMode?'':`<fieldset class="vw-character-choices"><legend>Pick a character</legend>${Object.entries(characterTemplates).map(([id,style])=>`<label><input type="radio" name="character_choice" value="${id}" data-vw-character-template ${id==='host'?'checked':''}><span class="vw-character-swatch" style="--skin:${style.skin};--wardrobe:${style.wardrobe};--hair:${style.hair}" data-hair="${style.hair_style}" aria-hidden="true"></span><strong>${id[0].toUpperCase()+id.slice(1)}</strong></label>`).join('')}</fieldset>`;
    const photo=`<div class="vw-photo-source"><label class="vw-field"><span>Portrait photo</span><input type="file" data-vw-character-photo accept="image/jpeg,image/png,image/webp"></label>
      <p>Use a centered, front-facing photo. Studio adds a body and an animated mouth.</p>
      <img data-vw-photo-preview class="vw-photo-preview" alt="Selected portrait" hidden></div>`;
    return `<form data-vw-form="character" data-photo-source="${hasPhoto?asset.id:''}" ${photoMode?'data-require-photo':''} ${asset?'':'data-place-character'}><h2>${asset?'Customize a copy':photoMode?'Use a photo':'Choose your character'}</h2>
      ${presets}${photoMode?photo:''}
      <details class="vw-character-customize" ${asset?'open':''}><summary>Customize</summary>
        ${field('name','Character name',asset?asset.name+' copy':'','text')}
        <label class="vw-field"><span>Hair style</span><select name="hair_style">${[['curls','Curls'],['close','Close cut'],['high_top','High top']].map(([id,label])=>`<option value="${id}" ${draft.hair_style===id?'selected':''}>${label}</option>`).join('')}</select></label>
        <div class="vw-row three">${field('skin','Skin',draft.skin,'color')}${field('wardrobe','Jacket',draft.wardrobe,'color')}${field('hair','Hair',draft.hair,'color')}</div>
        ${photoMode?'':`<details class="vw-photo-choice"><summary>${photoOption}</summary>${photo}</details>`}
      </details>
      <p data-vw-character-error role="alert"></p><div class="vw-actions">${button('close','Cancel')}<button type="submit" class="vw-btn primary">${asset?'Save character':'Add to scene'}</button></div></form>`;
  }
  function updateHomeSection(selector,html,replaceFocused=false){
    const section=app.querySelector('.vw-home '+selector);
    if(section&&(replaceFocused||!section.contains(app.ownerDocument.activeElement))&&section.outerHTML!==html)section.outerHTML=html;
  }
  function productionTemplates(){
    return `<div class="vw-template-grid">${state.presets.filter(p=>p.project_template).map(p=>`<article class="vw-template"><h3>${esc(p.name)}</h3><p>${esc(p.description||'')}</p>${button('template','Use template',`data-id="${esc(p.key)}"`)}</article>`).join('')||(state.loaded?'<p>No show templates available.</p>':'<p>Loading show templates…</p>')}</div>`;
  }
  const priorStudio=R.studio;
  R.studio=id=>{
    const home=!id||['create','templates'].includes(id);
    const dashboard=document.querySelector('#lightek-studio-dashboard');
    if(!dashboard)document.body.classList.toggle('lt-visual',enabled()&&(home||/^\d+$/.test(String(id))));
    if(!enabled()||!home||(!ST.loaded&&!app.querySelector('.vw-home')))return priorStudio(id);
    if(!state.loaded&&!state.loading)load();
    if(!state.starterLoaded&&!state.starterLoading)starterPoll();
    const animation=animationStart(),projects=studioSceneRecords().filter(record=>!record.project.is_template);
    const formats='<option value="landscape">Landscape</option><option value="portrait">Portrait</option><option value="square">Square</option>';
    return `<main class="visual-workbench vw-home">
      <h1>${animation?'Make a scene':'What are we making?'}</h1>
      <p class="vw-home-intro">${animation?'Add a character, give them something to do, and watch your scene.':'Start a production or continue working on one below.'}</p>
      <form class="vw-start" data-vw-form="new" ${animation?'data-animation':''}>
        ${animation?`<button class="vw-btn primary" type="submit">Start a scene</button><details class="vw-start-options"><summary>Name your scene or change its format</summary><label class="vw-field"><span>Project name</span><input name="name" aria-label="Project name" placeholder="Optional" maxlength="120"></label><label class="vw-field"><span>Format</span><select name="format" aria-label="Production format">${formats}</select></label></details>`:
          `<label class="vw-field"><span>Project name</span><input name="name" aria-label="Project name" required maxlength="120"></label><label class="vw-field"><span>Format</span><select name="format" aria-label="Production format">${formats}<option value="audio">Audio</option></select></label><button class="vw-btn primary" type="submit">Create production</button>`}
      </form>
      <div class="vw-message" data-vw-message role="status" ${state.message?'':'hidden'}>${esc(state.message)}</div>
      <section class="vw-continue"><h2>Continue a scene</h2><div class="vw-projects">${projects.map(({scene,project})=>`<a class="vw-project" href="${sceneUrl(scene.id,window.LightekStudioProduction&&scene.settings?.studio_entry==='stage'?'stage':'')}"><h3>${esc(project.name)}</h3><small>${esc(scene.name)}</small><span>Open →</span></a>`).join('')||'<p class="vw-help">Scenes you make will appear here.</p>'}</div></section>
      <details class="vw-home-extra"><summary>Try an example scene</summary>${starterPanel()}</details>
      <details class="vw-home-extra"><summary>Start from a show template</summary>${[...new Map(studioSceneRecords().filter(r=>r.project.is_template).map(r=>[r.project.id,r.project])).values()].map(p=>`<article class="vw-template"><h3>${esc(p.name)}</h3>${button('episode','Create episode',`data-id="${p.id}"`)}</article>`).join('')}${productionTemplates()}</details>
      ${dashboard?`<a class="vw-btn" href="/dashboard/studio-broadcasting?site_id=${encodeURIComponent(dashboard.dataset.siteId)}">Production library</a>`:button('advanced','Advanced studio & publishing tools')}
    </main>`;
  };
  window.LightekStudioVisual={enabled,view,mountStage};
  const bridge=window.LightekStudioViewportBridge,priorSelect=bridge.selectObject;
  bridge.selectObject=id=>{if(!enabled()||!app.querySelector('.visual-workbench'))return priorSelect(id);ST.selectedObjectId=id===null?null:Number(id);state.clip=null;refresh();window.dispatchEvent(new CustomEvent('lightek:visual-selection'));};
  app.addEventListener('dragstart',e=>{const asset=e.target.closest('.vw-asset');if(asset)e.dataTransfer.setData('application/x-lightek-asset',asset.dataset.id);});
  app.addEventListener('click',e=>{const b=e.target.closest('[data-vw]');if(!b)return;const action=b.dataset.vw;
    if(action==='tab'){
      const guided=!!b.closest('[data-vw-guide]');
      state.tab=b.dataset.id;refresh();
      if(guided)app.querySelector('[data-vw-assets]')?.scrollIntoView?.({block:'nearest'});
      return;
    }
    if(action==='select'){
      const guided=!!b.closest('[data-vw-guide]');
      bridge.selectObject(Number(b.dataset.id));
      if(guided)app.querySelector('[data-vw-inspector]')?.scrollIntoView?.({block:'nearest'});
      return;
    }
    if(action==='clip'){state.clip=Number(b.dataset.index);ST.selectedObjectId=null;refresh();return;}
    if(action==='advanced'&&window.LightekStudioProduction){LightekStudioProduction.go('scene');return;}
    if(action==='return'&&window.LightekStudioProduction){LightekStudioProduction.go('stage');return;}
    if(action==='advanced'){state.advanced=true;document.body.classList.remove('lt-visual');ST.workspaceMode='3d';render(1);const back=document.createElement('div');back.className='vw-technical-back';back.innerHTML='<span>Advanced studio tools</span><button class="vw-btn" data-vw="return">Back to visual studio</button>';app.prepend(back);return;}
    if(action==='return'){state.advanced=false;render(1);return;}
    if(action==='layout'||action==='edit'){state.poll++;state.mode=action;window.LightekStudioTimeline.stop();showStage();return;}
    if(action==='stop'){window.LightekStudioTimeline.stop();return;}
    if(action==='save-template'||action==='episode'){const projectId=action==='episode'?Number(b.dataset.id):current().project.id;dialog(`<form data-vw-form="${action==='episode'?'episode':'save-template'}" data-project="${projectId}"><h2>${action==='episode'?'Create an episode':'Save your show setup'}</h2><p>${action==='episode'?'A new project with its own scenes, cast instances and recordings.':'Copy this project’s scenes, cast and direction into a reusable template.'}</p>${field('name',action==='episode'?'Episode name':'Show template name','','text')}<div class="vw-actions">${button('close','Cancel')}<button class="vw-btn primary">${action==='episode'?'Create episode':'Save template'}</button></div></form>`);return;}
    if(['create-character','create-photo','customize-character'].includes(action)){
      const asset=action==='customize-character'?state.assets.find(item=>item.id===Number(b.dataset.id)&&item.metadata?.performer_build):null;
      dialog(characterEditor(asset,action==='create-photo'));return;
    }
    if(action==='close'){b.closest('dialog').close();return;}
    run(async()=>{
      if(action==='starter-cast'){
        const retry=state.starter&&(state.starter.status==='failed'||state.starter.phase==='delayed');
        const name='Rain and Snow';
        const payload=retry?{retry_asset_id:state.starter.asset_id}:{name,request_key:state.starterKey||=key()};
        state.starter=await call('starter.scene.create',payload);notice('');updateHomeSection('.vw-starter-cast',starterPanel(),true);await starterPoll();
      }
      if(action==='refresh'||action==='more'){await load(action==='more');notice('Assets refreshed.');}
      if(action==='add')await addAsset(Number(b.dataset.id));
      if(action==='retry-character'){await call('cast.retry',{asset_id:Number(b.dataset.id)});await load();notice('Creating your character…');}
      if(action==='set'){const scene=current().scene;await call('blender.create',{recipe:b.dataset.id,scene_id:scene.id,lock_version:scene.lock_version,name:b.textContent,request_key:key()});await reload();notice('Set added. Orbit the stage to arrange your shot.');}
      if(action==='preview')await preview();
      if(action==='play-scene')await preview(true,true);
      if(action==='add-motion')await appendMotion(b.dataset.id,b);
      if(action==='play'){if(!timeline().clips.length)throw Error('Add media to the edit first. Use Save & watch take for a character performance.');state.mode='edit';showStage();await window.LightekStudioTimeline.play(Number(app.querySelector('[data-vw-playhead]').value));notice('Playing the media edit.');}
      if(action==='remove-clip'){const t=timeline();t.clips.splice(state.clip,1);window.LightekStudioTimeline.set(t);await window.LightekStudioTimeline.save();state.clip=null;refresh();notice('Clip removed.');}
      if(action==='template'){const result=await call('blender.preset.use',{key:b.dataset.id,mode:'new_project',request_key:key()});await reload();location.hash='#/studio/'+result.scene_id;render(1);notice('Production template opened. Add your cast and media.');}
      if(action==='export'){const edit=state.mode==='edit';if(edit)await window.LightekStudioTimeline.save();const result=await call(edit?'timeline.quote':'render.quote',{scene_id:current().scene.id,output:'movie'});window.LightekStudioApp.setQuote(result);if(window.LightekStudioProduction){LightekStudioProduction.go('deliver',undefined,true);return;}state.advanced=true;ST.workspaceMode='publish';document.body.classList.remove('lt-visual');render(1);}
    });
  });
  app.addEventListener('change',event=>{
    const field=event.target;
    if(!field.matches('[data-vw-character-template]'))return;
    for(const [name,value] of Object.entries(characterTemplates[field.value]))field.form.elements[name].value=value;
  });
  app.addEventListener('change',event=>{
    const input=event.target;
    if(input.matches('[data-vw-character-photo]')){
      const dialog=input.closest('dialog'),preview=dialog.querySelector('[data-vw-photo-preview]'),file=input.files[0];
      if(dialog.photoUrl)URL.revokeObjectURL(dialog.photoUrl);
      dialog.photoUrl=file?URL.createObjectURL(file):null;
      preview.hidden=!file;
      if(file)preview.src=dialog.photoUrl;
      else preview.removeAttribute('src');
      return;
    }
    if(!input.matches('[data-vw-upload]'))return;
    const file=input.files[0];if(!file)return;
    run(async()=>{
      if(file.size>250*1024*1024)throw Error('Choose a file smaller than 250 MB.');
      const uploaded=await uploadAsset(file);
      await call('asset.import',{signed_id:uploaded.signed_id,name:file.name,request_key:key()});
      await load();notice('Upload received. It will appear here when processing finishes.');
    });
  });
  app.addEventListener('input',e=>{if(e.target.matches('[data-vw-playhead]')){const value=Number(e.target.value);if(state.mode==='edit')window.LightekStudioTimeline.seek(value);app.querySelector('[data-vw-time]').textContent=`${Math.floor(value/60).toString().padStart(2,'0')}:${(value%60).toFixed(1).padStart(4,'0')}`;}});
  app.addEventListener('submit',e=>{const form=e.target.closest('[data-vw-form]');if(!form)return;e.preventDefault();const data=Object.fromEntries(new FormData(form)),kind=form.dataset.vwForm,scene=current()?.scene,object=selected(),clipIndex=state.clip;run(async()=>{
    if(kind==='new'){
      const native=!!window.LightekStudioProduction,animation=form.hasAttribute('data-animation');
      const name=data.name.trim()||(animation?'My scene':'');
      if(!name)throw Error('Give your project a name.');
      const originatingRoute=location.hash;
      const result=await call('project.create',{
        format:data.format||'landscape',...(animation?{studio_entry:'stage'}:{}),
        name,request_key:form.dataset.requestKey||=key()
      });
      await reload();
      if(location.hash!==originatingRoute)return;
      location.hash=sceneUrl(result.scene_id,native&&animation?'stage':'');render(1);
      notice(animation?'':'Import media to begin editing.');
    }
    if(kind==='episode'||kind==='save-template'){if(!data.name.trim())throw Error('Enter a name.');const result=await call(kind==='episode'?'template.use':'template.save',{project_id:Number(form.dataset.project),name:data.name.trim(),request_key:form.dataset.requestKey||=key()});form.closest('dialog').close();await reload();if(kind==='episode'){location.hash='#/studio/'+result.scene_id;render(1);}notice(kind==='episode'?'Your independent episode is ready.':'Show template saved. Find it under production templates on the Studio home screen.');}
    if(kind==='character'){
      const dialog=form.closest('dialog'),file=form.querySelector('[data-vw-character-photo]').files[0],submit=form.querySelector('button[type="submit"]');
      const defaultName=form.hasAttribute('data-require-photo')?'Photo character':data.character_choice?data.character_choice[0].toUpperCase()+data.character_choice.slice(1):'Character';
      const {character_choice,...settings}=data;
      const name=data.name.trim()||defaultName;
      const submitLabel=submit.textContent;
      if(form.hasAttribute('data-require-photo')&&!file){dialog.querySelector('[data-vw-character-error]').textContent='Choose a portrait photo.';return;}
      if(file?.size>10*1024*1024){dialog.querySelector('[data-vw-character-error]').textContent='Choose a photo up to 10 MB.';return;}
      submit.disabled=true;
      submit.textContent=file?'Uploading photo…':'Saving character…';
      const photoOptions={};
      try{
        if(file){
          if(form.uploadedPhoto?.file!==file)form.uploadedPhoto={file,signedId:(await uploadAsset(file)).signed_id};
          photoOptions.photo_signed_id=form.uploadedPhoto.signedId;
        }else if(form.dataset.photoSource)photoOptions.copy_photo_from=Number(form.dataset.photoSource);
        submit.textContent='Saving character…';
        const result=await call('cast.create',{...settings,name,...photoOptions,request_key:form.dataset.requestKey||=key()});
        if(scene&&result.asset_id&&form.hasAttribute('data-place-character'))pendingCharacters.set(placementKey(scene.id,result.asset_id),{sceneId:scene.id,assetId:result.asset_id,requestKey:key()});
        dialog.close();
        await load();state.tab='characters';refresh();
        notice(form.hasAttribute('data-place-character')?'Preparing your character for this scene.':'Preparing your character.');
      }catch(error){
        dialog.querySelector('[data-vw-character-error]').textContent=error.message;
      }finally{submit.disabled=false;submit.textContent=submitLabel;}
    }
    if(kind==='transform'){await bridge.commitTransform(object.id,{location:[0,1,2].map(i=>Number(data['p'+i]))});await reload();notice('Position saved.');}
    if(kind==='clip'){const t=timeline();Object.assign(t.clips[clipIndex],Object.fromEntries(Object.entries(data).map(([k,v])=>[k,Number(v)])));window.LightekStudioTimeline.set(t);await window.LightekStudioTimeline.save();refresh();notice('Clip saved.');}
    if(kind==='take'){if(!data.audio_asset_id)throw Error('Choose or upload a recording first.');const sourceIn=Number(data.source_in),recording=state.assets.find(asset=>asset.id===Number(data.audio_asset_id));
      const length=Math.min(Number(data.duration),Math.max(0,(recording?.metadata?.duration??Infinity)-sourceIn));
      if(length<.1)throw Error('Choose at least a tenth of a second from the recording.');
      const prior=object.definition.performance;
      const sameRecording=prior?.audio_asset_id===recording?.id&&prior?.source_in===sourceIn&&Math.abs(prior?.duration-length)<1e-6;
      if(prior&&sameRecording&&prior.start===Number(data.start)){await preview(true);return;}
      if(object.definition.performance_takes?.length>1)throw Error('Use Cast to review this character’s recorded takes.');
      const lipSync=sameRecording&&prior.lip_sync?.analysis_id
        ? {lip_sync_mode:'phoneme',analysis_id:prior.lip_sync.analysis_id,mouth_cues:prior.lip_sync.cues} : {};
      await call('performance.save',{
        scene_id:scene.id,object_id:object.id,lock_version:scene.lock_version,audio_asset_id:Number(data.audio_asset_id),
        source_in:sourceIn,source_out:sourceIn+length,start:Number(data.start),gain:prior?.gain??1,
        expressions:sameRecording?prior?.expressions||[]:[],gestures:sameRecording?prior?.gestures||[]:[],
        ...lipSync,request_key:key()
      });await reload();await preview(true);}
  });});
  const advancedObserver=new MutationObserver(()=>{if(!window.LightekStudioProduction&&state.advanced&&location.hash.startsWith('#/studio')&&!app.querySelector('.vw-technical-back')){const back=document.createElement('div');back.className='vw-technical-back';back.innerHTML='<span>Advanced studio tools</span><button class="vw-btn" data-vw="return">Back to visual studio</button>';app.prepend(back);}});advancedObserver.observe(app,{childList:true});
  let drag=null;
  app.addEventListener('pointerdown',e=>{const b=e.target.closest('[data-vw=clip]');if(!b||e.button!==0)return;drag={index:Number(b.dataset.index),x:e.clientX,start:Number(timeline().clips[Number(b.dataset.index)].start),width:b.parentElement.getBoundingClientRect().width,total:duration(),sceneId:current().scene.id};});
  window.addEventListener('pointerup',e=>{if(!drag)return;const d=drag;drag=null;if(Math.abs(e.clientX-d.x)<5||d.sceneId!==current()?.scene.id||!d.width)return;run(async()=>{const t=timeline();t.clips[d.index].start=Math.max(0,Math.round((d.start+(e.clientX-d.x)/d.width*d.total)*100)/100);window.LightekStudioTimeline.set(t);await window.LightekStudioTimeline.save();refresh();notice('Clip moved.');});});
  window.addEventListener('hashchange',()=>{state.poll++;window.LightekStudioTimeline.stop();if(!location.hash.startsWith('#/studio'))document.body.classList.remove('lt-visual');});
  window.LightekStudioVisual.renderHomeInto=(root,html)=>{
    const home=root.querySelector('.vw-home');
    const openDialog=root.querySelector('.visual-workbench[data-vw-scene] dialog[open]');
    if(!home&&!openDialog)return false;
    const template=document.createElement('template');template.innerHTML=html;
    if(openDialog&&root.querySelector('[data-vw-scene]')?.dataset.vwScene===template.content.querySelector('[data-vw-scene]')?.dataset.vwScene)return true;
    if(!home)return false;
    const next=template.content.querySelector('.vw-home');if(!next||home.querySelector('[data-vw-form=new]')?.hasAttribute('data-animation')!==next.querySelector('[data-vw-form=new]')?.hasAttribute('data-animation'))return false;
    for(const selector of ['.vw-projects','.vw-template-grid','.vw-starter-cast']){const old=home.querySelector(selector),updated=next.querySelector(selector);if(old&&updated&&!old.contains(root.ownerDocument.activeElement)&&old.outerHTML!==updated.outerHTML)old.replaceWith(updated);}
    return true;
  };
})();
