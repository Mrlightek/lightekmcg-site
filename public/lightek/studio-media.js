(() => {
  const library={loaded:false,loading:false,items:[],builtins:[],cameras:[],demos:[],presets:[],error:'',query:'',category:'all',tab:'blender',presetLimit:18,runtime:null,nextBefore:null};
  let sceneId=null,timeline=null,preview=null;
  const timelineDrafts=new Map();
  const esc=v=>E(String(v??''));
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const run=fn=>Promise.resolve().then(fn).catch(error=>toast(error.message));
  const field=(label,value,attrs,type='number')=>`<label class="fld"><span>${esc(label)}</span><input type="${type}" step="any" value="${esc(value)}" ${attrs}></label>`;
  const previousPrepare=LightekStudioApp.prepare;
  LightekStudioApp.prepare=record=>{previousPrepare(record);if(sceneId!==record.scene.id){if(sceneId&&timeline)timelineDrafts.set(sceneId,{timeline:JSON.parse(JSON.stringify(timeline)),edit:JSON.parse(JSON.stringify(edit))});sceneId=record.scene.id;timeline=JSON.parse(JSON.stringify(timelineDrafts.get(sceneId)?.timeline||record.scene.settings.timeline||{output:'video',width:1280,height:720,clips:[]}));stopPreview();}};
  async function loadAssets(force=false,before=null){
    if(library.loading){if(force)library.reloadPending=true;return;}
    if(library.loaded&&!force&&!before)return;
    library.loading=true;
    try{const data=await call('assets.list',before?{before}:{});if(!Array.isArray(data.assets))throw Error('The asset library response was incomplete.');library.items=before?[...library.items,...data.assets.filter(item=>!library.items.some(existing=>existing.id===item.id))]:data.assets;library.nextBefore=data.next_before;library.builtins=data.builtins||[];library.cameras=data.camera_presets||[];library.demos=data.blender_demos||[];library.presets=data.media_presets||[];library.loaded=true;library.error='';if(!library.runtime)call('blender.runtime.status').then(value=>{if(typeof value?.ready==='boolean'){library.runtime=value;if(location.hash==='#/studio/library')render(1);}}).catch(()=>{});}
    catch(error){library.error=error.message;library.loaded=true;}
    finally{library.loading=false;if(location.hash.startsWith('#/studio'))render(1);if(library.reloadPending){library.reloadPending=false;queueMicrotask(()=>loadAssets(true));}}
    if(library.items.some(a=>a.status==='uploaded'||a.status==='processing'))setTimeout(()=>{if(location.hash.startsWith('#/studio'))loadAssets(true)},3000);
  }
  A.studioLibraryTab=button=>{library.tab=button.dataset.tab;library.query='';library.category='all';render(1);};
  A.studioPresetsMore=()=>{library.presetLimit+=18;render(1);};
  A.studioInstallBlenderLibrary=button=>run(async()=>{button.disabled=true;try{await call('blender.library.install');await loadAssets(true);toast('Official Blender collection imports queued');}finally{button.disabled=false;}});
  A.studioDemoOpen=button=>run(async()=>{button.disabled=true;try{const result=await call('blender.template.use',{asset_id:Number(button.dataset.id),request_key:button.dataset.requestKey||=crypto.randomUUID()});await A.studioLoad(true);ST.workspaceMode='3d';location.hash='#/studio/'+result.scene_id;render(1);}finally{button.disabled=false;}});
  A.studioAssetsReload=()=>run(()=>{library.runtime=null;return loadAssets(true);});
  A.studioAssetsMore=()=>run(()=>loadAssets(false,library.nextBefore));
  const previousAfter=AF.studio;
  AF.studio=id=>{previousAfter(id);if(me()&&!app.querySelector('.visual-workbench'))loadAssets();};
  const sceneOptions=()=>studioSceneRecords().filter(record=>!window.LightekStudioProduction||!current()||record.scene.id===current().scene.id).map(record=>`<option value="${record.scene.id}">${esc(record.project.name)} · ${esc(record.scene.name)}</option>`).join('');
  const objectOptions=(id,category)=>(studioSceneRecord(Number(id))?.scene.objects||[]).filter(object=>category!=='materials'||['cube','sphere','cylinder','plane'].includes(object.object_type||object.type)).map(object=>`<option value="${object.id}">${esc(object.name)}</option>`).join('');
  const targetScene=()=>`<label class="fld"><span>Use in scene</span><select name="scene_id" required data-library-scene>${sceneOptions()}</select></label>`;
  const noScenes=()=>!studioSceneRecords().length;
  function builtinCard(item){return `<article class="pwa-post" data-library-key="${esc(item.key)}"><span class="eb">${esc(item.category.replaceAll('_',' '))}</span><h3>${esc(item.name)}</h3><p>${esc(item.description)}</p><form data-media-form="builtin" data-key="${esc(item.key)}">${targetScene()}${item.target==='object'?`<label class="fld"><span>Target scene element</span><select name="object_id" required data-library-object>${objectOptions(studioSceneRecords()[0]?.scene.id,item.category)}</select></label>`:''}${item.key==='gfx_lower_thirds'?'<label class="fld"><span>Title</span><input name="title" maxlength="30" value="LIGHTEK LIVE"></label><label class="fld"><span>Guest / subtitle</span><input name="subtitle" maxlength="42" value="GUEST NAME"></label>':''}<button class="btn p sm" ${noScenes()?'disabled':''}>${item.target==='object'?'Apply to element':item.target==='timeline'?'Generate & add to timeline':'Add to scene'}</button><p role="status" data-library-status></p></form></article>`;}
  function jsonPresetCard(item){return `<article class="pwa-post" data-json-preset="${esc(item.key)}"><span class="eb">${esc(item.category.replaceAll('_',' '))}</span><h3>${esc(item.name)}</h3><p>${esc(item.production?.summary||item.description)}</p>${item.scene_count?`<p>${Number(item.scene_count)} scene setups</p>`:''}${item.production?.notes?`<p>${esc(item.production.notes)}</p>`:''}<small>${esc(item.key)} · ${esc(item.source_archive)}</small><p>${(item.output_summary||[]).map(esc).join(' · ')}</p><form data-media-form="json-preset" data-key="${esc(item.key)}"><label class="fld"><span>Use template</span><select name="mode"><option value="new_project">Create a new production</option>${noScenes()?'':'<option value="apply">Apply inside a saved scene</option><option value="new_scenes">Add scenes to an existing project</option>'}</select></label><label class="fld"><span>Production name / title</span><input name="name" maxlength="120" value="${esc(item.name)}"></label>${noScenes()?'':targetScene()}${['material','material_catalog','material_style'].includes(item.category)&&!noScenes()?`<label class="fld"><span>Apply material to element · optional</span><select name="object_id" data-library-object><option value="">Create reusable Blender material</option>${objectOptions(studioSceneRecords()[0]?.scene.id,'materials')}</select></label>`:''}${item.requires_asset?`<label class="fld"><span>Library file for this template</span><select name="asset_id" required>${library.items.filter(asset=>asset.status==='ready'&&(['audio_pack','audio_package'].includes(item.category)?asset.kind==='audio':asset.kind==='blend'&&asset.native_url)).map(asset=>`<option value="${asset.id}">${esc(asset.name)}</option>`).join('')}</select></label>`:''}<button class="btn p sm">${item.project_template?'Create production from template':'Use Blender preset / template'}</button><p role="status" data-library-status></p></form></article>`;}
  function cameraCard(camera){return `<article class="pwa-post"><span class="eb">Blender camera</span><h3>${esc(camera.name)}</h3><p>${esc(camera.settings.camera_type)} · ${Number(camera.settings.lens)}mm · ${Number(camera.settings.sensor_width)}mm sensor</p><form data-media-form="camera-create" data-preset="${esc(camera.key)}">${targetScene()}<label class="fld"><span>Camera name</span><input name="name" maxlength="120" value="${esc(camera.name)}"></label><button class="btn p sm" ${noScenes()?'disabled':''}>Add Blender camera</button><p role="status" data-library-status></p></form></article>`;}
  function demoCard(demo){const asset=library.items.find(item=>item.metadata?.demo_key===demo.key),pending=asset&&['uploaded','processing'].includes(asset.status);return `<article class="pwa-post" data-blender-demo="${esc(demo.key)}">${asset?.thumbnail_url?`<img class="pwa-media" src="${esc(asset.thumbnail_url)}" alt="${esc(demo.name)}">`:''}<span class="eb">Native Blender file</span><h3>${esc(demo.name)}</h3><p>${esc(demo.description)}</p><p>${esc(demo.author)} · ${esc(demo.license)} · Blender ${esc(demo.minimum_blender)}+</p><a href="${esc(demo.source_page)}" target="_blank" rel="noopener noreferrer">Original collection ↗</a><p>${asset?`Library status: ${esc(asset.status)}`:'Ready to download from Blender'}</p>${asset?.error?`<p role="alert">${esc(asset.error)}</p>`:''}${asset?.status==='ready'?`<button type="button" class="btn p" data-a="studioDemoOpen" data-id="${asset.id}">Open editable Blender project</button><a class="btn sm" href="${esc(asset.native_url)}" download>Download .blend</a>`:`<button type="button" class="btn p sm" data-a="studioBlenderDemoImport" data-key="${esc(demo.key)}" ${pending?'disabled':''}>${pending?'Import queued':asset?.status==='failed'?'Retry import':'Import native Blender file'}</button>`}</article>`;}
  function nativeControls(asset){
    if(asset.kind!=='blend')return '';
    if(!asset.metadata.native_blender||!asset.native_url)return `<button type="button" class="btn sm" data-a="studioBlenderPrepare" data-id="${asset.id}">Prepare native Blender source</button>`;
    const scenes=asset.metadata.scenes||[],credit=asset.metadata.source;
    return `<section><h4>Native Blender source</h4>${!asset.metadata.authoring_version?`<button type="button" class="btn sm" data-a="studioBlenderPrepare" data-id="${asset.id}">Refresh Blender object metadata</button>`:''}<p>${scenes.length} scenes · Blender ${esc(asset.metadata.blender_version)} · original nodes, materials, rigs and cameras retained</p>${credit?`<p>${esc(credit.author)} · ${esc(credit.license)} · <a href="${esc(credit.source_page)}" target="_blank" rel="noopener noreferrer">Source credits</a></p>`:''}${(asset.metadata.missing_dependencies||[]).length?`<p role="alert">Missing dependencies: ${esc(asset.metadata.missing_dependencies.join(', '))}</p>`:''}${(asset.metadata.warnings||[]).map(message=>`<p>${esc(message)}</p>`).join('')}<a class="btn sm" href="${esc(asset.native_url)}" download>Download editable .blend</a>${asset.bundle_url?`<a class="btn sm" href="${esc(asset.bundle_url)}" download>Download source bundle</a>`:''}<form data-media-form="native-template" data-id="${asset.id}"><label class="fld"><span>New production name</span><input name="name" required maxlength="120" value="${esc(asset.name)}"></label><label class="fld"><span>Native Blender scene</span><select name="source_scene"><option value="">All source scenes</option>${scenes.map(scene=>`<option value="${esc(scene.name)}">${esc(scene.name)} · ${scene.object_count} objects · ${scene.cameras.length} cameras</option>`).join('')}</select></label><button class="btn p sm">Create editable production</button><p role="status" data-library-status></p></form>${(asset.metadata.readmes||[]).map(readme=>`<details><summary>${esc(readme.name)}</summary><pre style="white-space:pre-wrap;max-height:240px;overflow:auto">${esc(readme.text)}</pre></details>`).join('')}</section>`;
  }
  function assetCard(asset){
    const model=['glb','blend'].includes(asset.kind),media=['audio','image','video'].includes(asset.kind);
    const ready=asset.status==='ready';
    const preview=ready?(model&&asset.proxy_url?`<button type="button" class="btn sm" data-a="studioAssetPreview" data-id="${asset.id}">3D preview</button>`:model?'':asset.kind==='image'?`<img class="pwa-media" src="${esc(asset.proxy_url)}" alt="${esc(asset.name)}">`:`<${asset.kind==='audio'?'audio':'video'} class="pwa-media" src="${esc(asset.proxy_url)}" controls playsinline preload="metadata"></${asset.kind==='audio'?'audio':'video'}>`):'';
    const use=ready?`<form data-media-form="${model?'place':'use'}" data-id="${asset.id}">${targetScene()}${model?`<label class="fld"><span>Production role</span><select name="category">${['character','environment','prop','vehicle','architecture','geometry'].map(name=>`<option>${name}</option>`).join('')}</select></label>`:`<label class="fld"><span>Timeline placement</span><select name="placement"><option value="append">After the current sequence</option><option value="overlay">Layer / mix from the start</option></select></label>`}<button class="btn p sm" ${noScenes()?'disabled':''}>${model?'Place in scene':'Add to timeline'}</button>${media?`<button type="button" class="btn sm" data-a="studioAssetPublish" data-id="${asset.id}" ${noScenes()?'disabled':''}>Publish / schedule</button>`:''}<p role="status" data-library-status></p></form>`:'';
    return `<article class="pwa-post"><h3>${esc(asset.name)}</h3><p>${esc(asset.kind)} · ${esc(asset.status)}</p>${asset.error?`<p role="alert">${esc(asset.error)}</p>`:''}${asset.thumbnail_url&&asset.kind!=='image'?`<img class="pwa-media" src="${esc(asset.thumbnail_url)}" alt="">`:''}${preview}${nativeControls(asset)}${use}<div class="pwa-post-actions">${asset.url?`<a class="btn sm" href="${esc(asset.url)}" download>Download original</a>`:''}${ready&&(media||model&&asset.proxy_url)?`<a class="btn sm" href="/dashboard/live?library_asset_id=${asset.id}">Use in Live Studio</a>`:''}${asset.status==='failed'?`<button type="button" class="btn sm" data-a="studioAssetRetry" data-id="${asset.id}">Retry processing</button>`:''}</div><div data-preview-for="${asset.id}"></div></article>`;
  }
  const previousStudio=R.studio;
  R.studio=id=>{
    if(id==='templates'&&meProfile()&&ST.loaded){
      const productions=library.presets.filter(item=>item.project_template||['production_template','production_preset','industry_pack','show_bible','broadcast_package'].includes(item.category));
      return `<section class="wrap pwa-page"><span class="eb">LIGHTEK / PRODUCTION TEMPLATES</span><h1>Your first shot starts with a plan.</h1><p>Choose a complete production setup. Studio creates independent scenes, cameras and lighting from your JSON packs; Lightek production packages also include shot plans, music cue sheets, performance cues, branding and audio tracks. Replace the blocking assets with your cast and footage.</p><div class="pwa-post-actions"><a class="btn" href="#/studio/create">Start from scratch</a><a class="btn" href="#/studio/library">All JSON presets & media</a></div>${library.error?`<p role="alert">${esc(library.error)}</p>`:''}<div class="g3">${productions.map(production=>jsonPresetCard(production)).join('')||'<p role="status">Loading production templates…</p>'}</div></section>`+previousStudio(id);
    }
    if(id!=='library'||!meProfile()||!ST.loaded){const page=previousStudio(id);return meProfile()&&ST.loaded&&(id==='create'||!id)?`<div class="wrap pwa-post-actions"><a class="btn p" href="#/studio/templates">Start from a production template</a><span>Sets, cameras and a scene structure ready to customize.</span></div>`+page:page;}
    const match=item=>(library.category==='all'||item.category===library.category||item.kind===library.category)&&[item.name,item.description,item.kind,item.category].join(' ').toLowerCase().includes(library.query.toLowerCase());
    const categories=[...new Set([...library.builtins.map(item=>item.category),...library.presets.map(item=>item.category),...library.items.map(item=>item.kind)])].sort();
    const tabs=[['blender','Blender files'],['presets','Presets & recipes'],['media','My media'],['projects','Saved projects']];
    const demoSection=`<section><h2>Official Blender templates</h2><p>Real .blend projects with native objects, cameras, materials and node graphs. Open an installed file or import it into your library.</p><button class="btn" data-a="studioInstallBlenderLibrary">Install full Blender collection</button>${library.runtime?`<p class="pwa-empty" role="status">${library.runtime.ready?'Blender engine ready':esc(library.runtime.message)}</p>`:''}<div class="g3">${library.demos.filter(item=>!library.query||item.name.toLowerCase().includes(library.query.toLowerCase())).map(demoCard).join('')||'<p>Loading Blender collection…</p>'}</div><h2>Your native Blender files</h2><div class="g3">${library.items.filter(item=>item.kind==='blend'&&match(item)).map(assetCard).join('')||'<p>No Blender files installed yet. Import a template above to begin.</p>'}</div></section>`;
    const presets=library.presets.filter(match);
    const presetSection=`<section><h2>JSON media presets & project templates</h2><p>Apply native cameras, scene staging, materials, titles, nodes and frame markers. Each preset lists what it creates.</p><div class="g3">${presets.slice(0,library.presetLimit).map(jsonPresetCard).join('')||'<p>No presets match.</p>'}</div>${presets.length>library.presetLimit?'<button class="btn" data-a="studioPresetsMore">Show more presets</button>':''}<h2>Blender cameras</h2><div class="g3">${library.cameras.map(cameraCard).join('')}</div><h2>Production recipes</h2><div class="g3">${library.builtins.filter(match).map(builtinCard).join('')}</div></section>`;
    const mediaSection=`<section><h2>Import your media</h2><form data-media-form="import" class="pwa-post"><label class="fld"><span>Name</span><input name="name" maxlength="160"></label><label class="fld"><span>Image, audio, video, .blend, .glb or a Blender resource ZIP · up to 250 MB</span><input type="file" name="file" accept="image/*,audio/*,video/*,.blend,.glb,.zip" required></label><button class="btn p">Import asset</button><p role="status" data-import-status></p></form><h2>Your imported & generated media</h2><div class="g3">${library.items.filter(match).map(assetCard).join('')||'<p>No media matches.</p>'}</div>${library.nextBefore?'<button class="btn" data-a="studioAssetsMore">Load more media</button>':''}</section>`;
    const projects=`<section><h2>Saved projects & scenes</h2><div class="g3">${ST.projects.map(project=>`<article class="pwa-post"><h3>${esc(project.name)}</h3>${(project.scenes||studioSceneRecords().filter(record=>record.project.id===project.id).map(record=>record.scene)).map(scene=>`<a class="btn sm" href="#/studio/${scene.id}">${esc(scene.name)}</a>`).join(' ')}</article>`).join('')||'<p>No saved projects yet.</p>'}</div></section>`;
    return `<div class="wrap pwa-page"><span class="eb">Lightek Studio / Asset Browser</span><h1>Build with what you have.</h1><p>Open a native Blender project, apply a preset, or bring your own media.</p><div class="pwa-post-actions"><a class="btn p" href="#/studio/workshop">Create shapes, sets & effects</a><a class="btn" href="#/studio">Back to productions</a><a class="btn" href="#/studio/templates">Saved project templates</a><button class="btn" data-a="studioAssetsReload">Refresh library</button></div><nav class="pwa-post-actions" aria-label="Studio library sections">${tabs.map(([key,label])=>`<button type="button" class="btn ${library.tab===key?'p':''}" data-a="studioLibraryTab" data-tab="${key}" aria-pressed="${library.tab===key}">${label}</button>`).join('')}</nav><form data-media-form="filter" class="pwa-post-actions"><label class="fld"><span>Find an item</span><input name="query" type="search" value="${esc(library.query)}" placeholder="Search library"></label><label class="fld"><span>Category</span><select name="category"><option value="all">All items</option>${categories.map(category=>`<option value="${esc(category)}" ${category===library.category?'selected':''}>${esc(category.replaceAll('_',' '))}</option>`).join('')}</select></label><button class="btn sm">Filter</button></form>${library.error?`<p role="alert">${esc(library.error)}</p>`:''}${library.tab==='blender'?demoSection:library.tab==='presets'?presetSection:library.tab==='media'?mediaSection:projects}</div>`;
  };
  A.studioBlenderDemoImport=button=>run(async()=>{button.disabled=true;try{const result=await call('blender.demo.import',{demo_key:button.dataset.key});await loadAssets(true);toast(`Blender import ${result.status}`);}finally{button.disabled=false;}});
  A.studioBlenderPrepare=button=>run(async()=>{await call('blender.prepare',{asset_id:Number(button.dataset.id)});await loadAssets(true);toast('Native Blender preparation queued');});
  A.studioAssetRetry=button=>run(async()=>{await call('asset.retry',{asset_id:Number(button.dataset.id)});await loadAssets(true);toast('Processing queued');});
  A.studioBuiltinQuick=button=>run(async()=>{const record=current();if(!record)throw Error('Open a saved scene first.');const result=await call('library.apply',{key:button.dataset.key,scene_id:record.scene.id,lock_version:record.scene.lock_version,object_id:studioWorkspaceSelectedObject(record.scene)?.id,request_key:crypto.randomUUID()});timelineDrafts.delete(result.scene_id);sceneId=null;await A.studioLoad(true);LightekStudioApp.applied?.(result,{key:button.dataset.key});});
  A.studioJsonPresetQuick=button=>run(async()=>{const record=current();if(!record)throw Error('Open a saved scene first.');const key=document.getElementById('studio-json-preset-select').value,beforeIds=record.scene.objects.map(object=>object.id);const result=await call('blender.preset.use',{key,mode:'apply',scene_id:record.scene.id,lock_version:record.scene.lock_version,object_id:studioWorkspaceSelectedObject(record.scene)?.id,request_key:crypto.randomUUID()});timelineDrafts.delete(result.scene_id);sceneId=null;await A.studioLoad(true);LightekStudioApp.applied?.(result,{key,preset:true,beforeIds});});
  const previousShelf=LightekStudioApp.tools;
  LightekStudioApp.tools=(...args)=>`${previousShelf?previousShelf(...args):''}<section class="pwa-post"><h3>Blender JSON presets</h3><select id="studio-json-preset-select" aria-label="Blender JSON preset">${library.presets.filter(item=>!item.requires_asset).map(item=>`<option value="${esc(item.key)}">${esc(item.name)}</option>`).join('')}</select><button class="btn sm" data-a="studioJsonPresetQuick">Apply to this scene / selected element</button><a class="btn sm" href="#/studio/library">All project templates</a></section>`;
  const productionTools=LightekStudioApp.tools;
  LightekStudioApp.tools=(record,...args)=>{
    const content=productionTools(record,...args),brief=record?.scene?.settings?.production_brief;
    if(!brief)return content;
    return `<details class="pwa-post" open><summary>Production plan · ${esc(brief.branding?.series_title||'Lightek')}</summary><h3>${esc(brief.segment?.name||record.scene.name)}</h3><p>${esc(brief.segment?.brief||brief.production?.summary||'')}</p><p>${esc(brief.production?.notes||'')}</p><p>Scene duration: ${Number(brief.segment?.duration_seconds||0)} s · Episode position: ${Number(brief.segment?.episode_start_seconds||0)} s</p><h4>Camera coverage</h4><ol>${(brief.coverage||[]).map(shot=>`<li>${esc(shot.name)} · ${Number(shot.lens)} mm · ${Number(shot.start_seconds||0)}–${Number((shot.start_seconds||0)+(shot.duration_seconds||0))} s</li>`).join('')}</ol><h4>Music cue sheet</h4><ul>${(brief.segment?.music_cues||[]).map(cue=>`<li>${Number(cue.start)}–${Number(cue.end)} s · ${esc(cue.purpose)} · ${Number(cue.tempo_bpm)} BPM · ${esc(cue.meter)} · ${esc(cue.instrumentation)} · ${esc(cue.dynamic)}<p>${esc(cue.sync)}</p></li>`).join('')}</ul><h4>Performance cues</h4><ul>${(brief.segment?.performance_cues||[]).map(cue=>`<li>${Number(cue.time)} s · ${esc(cue.direction)}</li>`).join('')}</ul><p>Choose a camera in the Outliner to adjust the shot. Import your cast, dialogue and music in Library, then assemble the sequence in Timeline.</p></details>`+content;
  };
  A.studioArtifactReuse=button=>run(async()=>{
    button.disabled=true;
    try{await call('artifact.reuse',{project_id:Number(button.dataset.project),artifact_id:Number(button.dataset.artifact)});library.tab='media';library.loaded=false;location.hash='#/studio/library';await loadAssets(true);toast('Render added to your editing library. Add it to a timeline when preparation finishes.');}finally{button.disabled=false;}
  });
  A.studioAssetPublish=button=>{
    const asset=library.items.find(item=>item.id===Number(button.dataset.id)),scene=button.closest('form').elements.scene_id.value;
    if(!scene)return toast('Choose a scene first.');
    const dialog=document.createElement('dialog');dialog.className='pwa-publish-dialog';dialog.innerHTML=`<form data-media-form="publish" data-id="${asset.id}" data-scene="${scene}"><h2>Publish ${esc(asset.name)}</h2><label class="fld"><span>Title</span><input name="title" required maxlength="160" value="${esc(asset.name)}"></label><label class="fld"><span>Destination</span><select name="platform"><option value="lightek_social">Lightek profile & community</option>${asset.kind==='video'?'<option value="lightek_streaming">Lightek OTT</option><option value="octavia">Octavia</option>':''}</select></label><label class="fld"><span>Audience</span><select name="audience"><option value="everyone">Everyone</option><option value="women">Women only</option><option value="men">Men only</option></select></label><label class="fld"><span>Community slug · optional</span><input name="community_slug" maxlength="100"></label><label><input type="checkbox" name="spatial"> Include current interactive scene · Lightek social</label><label><input type="checkbox" name="spatial_rights"> I have permission to share the included 3D assets</label><label><input type="checkbox" name="allow_remix"> Allow Fork Scene and asset reuse under CC-BY-4.0</label><label class="fld"><span>Release time · optional</span><input type="datetime-local" name="publish_at"></label><p>OTT playback requires an MP4. Other video formats can be exported from a timeline first.</p><button class="btn p">Queue publication</button><button type="button" class="btn" data-library-close>Cancel</button><p role="status" data-library-status></p></form>`;dialog.querySelector('[data-library-close]').onclick=()=>dialog.close();dialog.addEventListener('close',()=>dialog.remove());app.append(dialog);dialog.showModal();
  };
  A.studioAssetPreview=b=>{
    const asset=library.items.find(a=>a.id===Number(b.dataset.id));const root=app.querySelector(`[data-preview-for="${asset.id}"]`);
    root.innerHTML=`<div class="pwa-model-preview" data-asset-preview="${esc(asset.proxy_url)}"><p role="status">Loading model…</p></div>`;
  };
  const edit = {selected:0, playhead:0, undo:[], redo:[]};
  const clone=value=>JSON.parse(JSON.stringify(value));
  const lengthOf=clip=>(clip.out-clip.in)/(clip.speed||1);
  const sequenceDuration=()=>Math.max(0,...timeline.clips.map(c=>c.start+lengthOf(c)));
  const snap=value=>Math.round(value*(timeline.fps||24))/(timeline.fps||24);
  const checkpoint=()=>{stopPreview();edit.undo.push(clone(timeline));if(edit.undo.length>60)edit.undo.shift();edit.redo=[];};
  const trackFor=id=>{timeline.tracks||=[];let track=timeline.tracks.find(t=>t.id===id);if(!track){track={id,name:`Track ${id+1}`,gain:1,pan:0,muted:false,solo:false};timeline.tracks.push(track);}return track;};
  const priorMediaPrepare=LightekStudioApp.prepare;
  LightekStudioApp.prepare=record=>{const changed=sceneId!==record.scene.id;priorMediaPrepare(record);if(changed)Object.assign(edit,{selected:0,playhead:0,undo:[],redo:[]},timelineDrafts.get(sceneId)?.edit||{});};
  if(!STUDIO_WORKSPACE_MODES.some(mode=>mode.key==='timeline'))STUDIO_WORKSPACE_MODES.splice(5,0,{key:'timeline',label:'Timeline',description:'Edit footage, finish color, title and mix a production.'});
  const previousStory=LightekStudioApp.story;
  const choice=(key,values,selected)=>`<select data-timeline-setting="${key}">${values.map(([value,label])=>`<option value="${value}" ${String(value)===String(selected)?'selected':''}>${label}</option>`).join('')}</select>`;
  LightekStudioApp.story=(record,mode)=>{
    if(!['timeline','audio'].includes(mode))return previousStory(record,mode);
    const assets=library.items.filter(a=>a.status==='ready'&&['audio','video','image'].includes(a.kind));
    const duration=Math.max(1,sequenceDuration());
    const clip=timeline.clips[edit.selected],i=edit.selected;
    const trackIds=[...new Set([0,...timeline.clips.map(c=>c.track),...(timeline.tracks||[]).map(t=>t.id)])].sort((a,b)=>a-b);
    const clipFields=clip?`<details class="pwa-post" open><summary>Clip ${i+1} · ${esc(library.items.find(a=>a.id===clip.asset_id)?.name||'Media')}</summary><div class="pwa-editor-fields">${[['in','Source in · seconds',0],['out','Source out · seconds',5],['start','Timeline start · seconds',0],['track','Track · 0–15',0],['speed','Playback speed · 0.25–4',1],['gain','Volume · 1 = original',1],['fade_in','Fade in · seconds',0],['fade_out','Fade out · seconds',0],['x','Horizontal position',0],['y','Vertical position',0],['scale','Picture scale',1],['opacity','Opacity · 0–1',1],['brightness','Brightness · -1–1',0],['contrast','Contrast · 0–2',1],['saturation','Saturation · 0–3',1],['highpass','Low cut · Hz, 0 disables',0]].map(([key,label,fallback])=>field(label,clip[key]??fallback,`data-clip="${i}" data-clip-field="${key}"`)).join('')}<label><input type="checkbox" data-clip="${i}" data-clip-field="muted" ${clip.muted?'checked':''}> Mute clip audio</label><label><input type="checkbox" data-clip="${i}" data-clip-field="denoise" ${clip.denoise?'checked':''}> Export noise reduction</label></div><h4>Position and volume keyframes</h4>${(clip.keyframes||[]).map((frame,j)=>`<div class="pwa-editor-fields">${[['time','Time · seconds from clip start'],['x','X'],['y','Y'],['gain','Volume']].map(([key,label])=>field(label,frame[key],`data-clip="${i}" data-keyframe="${j}" data-frame-field="${key}"`)).join('')}<button class="btn sm" data-a="studioTimelineFrameRemove" data-index="${i}" data-frame="${j}">Remove keyframe</button></div>`).join('')}<div class="pwa-post-actions"><button class="btn sm" data-a="studioTimelineFrame" data-index="${i}">Keyframe at playhead</button><button class="btn sm" data-a="studioTimelineSplit">Split at playhead</button><button class="btn sm" data-a="studioTimelineDuplicate">Duplicate after clip</button><button class="btn sm" data-a="studioTimelineRemove" data-index="${i}">Remove clip</button></div></details>`:'<p>Import or select media to start your sequence.</p>';
    return `<section class="studio-wave2 studio-finish"><span class="eb">${mode==='audio'?'Audio & mix':'Editing & finishing'}</span><h2>Shape the sequence.</h2><div class="pwa-post-actions"><select id="timeline-asset" aria-label="Asset">${assets.map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.kind)}</option>`).join('')}</select><button class="btn sm" data-a="studioTimelineAdd">Add clip</button><a class="btn sm" href="#/studio/library">Import media</a><button class="btn sm" data-a="studioTimelineUndo" ${edit.undo.length?'':'disabled'}>Undo</button><button class="btn sm" data-a="studioTimelineRedo" ${edit.redo.length?'':'disabled'}>Redo</button><button class="btn sm" data-a="studioTimelineSave">Save timeline</button><button class="btn sm" data-a="studioTimelinePreview">Play preview</button><button class="btn sm" data-a="studioTimelineStop">Stop preview</button><button class="btn p sm" data-a="studioTimelineQuote">Export quote</button></div><div class="pwa-editor-fields"><label>Output ${choice('output',[['video','Video + mixed audio'],['audio','WAV audio mix']],timeline.output)}</label><label>Delivery ${choice('export_preset',[['review','H.264 MP4 / 16-bit WAV'],['master','ProRes 422 HQ MOV / 24-bit WAV']],timeline.export_preset||'review')}</label><label>Frame rate ${choice('fps',[24,25,30,48,50,60].map(v=>[v,`${v} fps`]),timeline.fps||24)}</label>${field('Width',timeline.width,'data-timeline-setting="width"')}${field('Height',timeline.height,'data-timeline-setting="height"')}</div><canvas class="pwa-timeline-preview" width="${Math.min(960,Number(timeline.width))}" height="${Math.round(Number(timeline.height)*Math.min(1,960/Number(timeline.width)))}" data-timeline-preview></canvas><p role="status" data-timeline-status>64 clips · 16 tracks · up to 10 minutes per assembly. Browser preview is a proxy; export applies final color, noise reduction and limiting.</p><label class="fld"><span>Playhead · ${edit.playhead.toFixed(3)} s / ${duration.toFixed(3)} s</span><input aria-label="Playhead" type="range" min="0" max="${duration}" step="${1/(timeline.fps||24)}" value="${edit.playhead}" data-timeline-playhead></label><div class="pwa-timeline">${trackIds.map(track=>`<div class="pwa-timeline-track"><small>${esc((timeline.tracks||[]).find(t=>t.id===track)?.name||`Track ${track+1}`)}</small>${timeline.clips.map((c,index)=>c.track===track?`<button type="button" aria-pressed="${index===i}" class="pwa-timeline-bar ${index===i?'is-selected':''}" data-a="studioTimelineSelect" data-index="${index}" style="left:${c.start/duration*100}%;width:${Math.max(1,lengthOf(c)/duration*100)}%">${esc(library.items.find(a=>a.id===c.asset_id)?.name||'Clip')} · ${index+1}</button>`:'').join('')}</div>`).join('')}</div>${clipFields}<details class="pwa-post" open><summary>Track mixer · 48 kHz stereo</summary><p>Solo and mute affect audio. Use clip opacity for picture visibility.</p><div class="studio-mixer">${trackIds.map(id=>{const t=(timeline.tracks||[]).find(t=>t.id===id)||{name:`Track ${id+1}`,gain:1,pan:0};return `<fieldset><legend>Track ${id+1}</legend>${field('Name',t.name,`data-track="${id}" data-track-field="name"`,'text')}${field('Gain · 0–4',t.gain,`data-track="${id}" data-track-field="gain"`)}${field('Pan · -1 left / 1 right',t.pan,`data-track="${id}" data-track-field="pan"`)}${['muted','solo'].map(key=>`<label><input type="checkbox" data-track="${id}" data-track-field="${key}" ${t[key]?'checked':''}> ${key==='muted'?'Mute':'Solo'}</label>`).join('')}</fieldset>`;}).join('')}</div></details><details class="pwa-post" open><summary>Titles & captions</summary><button class="btn sm" data-a="studioTimelineTitleAdd">Add title at playhead</button>${(timeline.titles||[]).map((title,index)=>`<fieldset><legend>Title ${index+1}</legend><label class="fld"><span>Text</span><textarea maxlength="500" data-title="${index}" data-title-field="text">${esc(title.text)}</textarea></label><div class="pwa-editor-fields">${[['start','Start'],['end','End'],['x','X'],['y','Y'],['size','Font size']].map(([key,label])=>field(label,title[key],`data-title="${index}" data-title-field="${key}"`)).join('')}</div><button class="btn sm" data-a="studioTimelineTitleRemove" data-index="${index}">Remove title</button></fieldset>`).join('')}</details></section>`;
  };
  A.studioTimelineSelect=b=>{stopPreview();edit.selected=Number(b.dataset.index);edit.playhead=timeline.clips[edit.selected]?.start||0;render(1);};
  A.studioTimelineUndo=()=>{if(!edit.undo.length)return;stopPreview();edit.redo.push(clone(timeline));timeline=edit.undo.pop();edit.selected=0;render(1);};
  A.studioTimelineRedo=()=>{if(!edit.redo.length)return;stopPreview();edit.undo.push(clone(timeline));timeline=edit.redo.pop();edit.selected=0;render(1);};
  A.studioTimelineAdd=()=>{const asset=library.items.find(a=>a.id===Number(document.getElementById('timeline-asset').value));if(!asset)return;checkpoint();timeline.clips.push({asset_id:asset.id,kind:asset.kind,in:0,out:asset.kind==='image'?5:Math.min(asset.metadata.duration||5,5),start:snap(sequenceDuration()),track:0,gain:1,x:0,y:0,muted:false,keyframes:[]});edit.selected=timeline.clips.length-1;render(1);};
  A.studioTimelineRemove=b=>{checkpoint();timeline.clips.splice(Number(b.dataset.index),1);edit.selected=Math.max(0,Math.min(edit.selected,timeline.clips.length-1));render(1);};
  A.studioTimelineDuplicate=()=>{const clip=timeline.clips[edit.selected];if(!clip)return;checkpoint();const next=clone(clip);next.start=snap(clip.start+lengthOf(clip));timeline.clips.push(next);edit.selected=timeline.clips.length-1;render(1);};
  A.studioTimelineSplit=()=>{
    const clip=timeline.clips[edit.selected];if(!clip)return;
    const offset=snap(edit.playhead-clip.start),length=lengthOf(clip);
    if(offset<=0||offset>=length)return toast('Place the playhead inside the selected clip.');
    checkpoint();const next=clone(clip),cut=clip.in+offset*(clip.speed||1);
    const boundary={time:offset,x:interpolate(clip.keyframes,'x',offset,clip.x||0),y:interpolate(clip.keyframes,'y',offset,clip.y||0),gain:interpolate(clip.keyframes,'gain',offset,clip.gain??1)};
    const frames=clip.keyframes||[];
    clip.out=cut;next.in=cut;next.start=clip.start+offset;
    clip.keyframes=frames.length?[...frames.filter(f=>f.time<offset),boundary]:[];
    next.keyframes=frames.length?[{...boundary,time:0},...frames.filter(f=>f.time>offset).map(f=>({...f,time:f.time-offset}))]:[];
    clip.fade_out=0;next.fade_in=0;clip.fade_in=Math.min(clip.fade_in||0,offset);next.fade_out=Math.min(next.fade_out||0,length-offset);
    timeline.clips.splice(edit.selected+1,0,next);edit.selected++;render(1);
  };
  A.studioTimelineFrame=b=>{const clip=timeline.clips[Number(b.dataset.index)],time=snap(edit.playhead-clip.start);if(time<0||time>lengthOf(clip))return toast('Place the playhead inside this clip.');if((clip.keyframes||[]).some(f=>Math.abs(f.time-time)<0.00001))return toast('A keyframe already exists here.');checkpoint();clip.keyframes||=[];clip.keyframes.push({time,x:clip.x||0,y:clip.y||0,gain:clip.gain??1});clip.keyframes.sort((a,b)=>a.time-b.time);render(1);};
  A.studioTimelineFrameRemove=b=>{checkpoint();timeline.clips[Number(b.dataset.index)].keyframes.splice(Number(b.dataset.frame),1);render(1);};
  A.studioTimelineTitleAdd=()=>{const end=sequenceDuration(),start=snap(edit.playhead);if(start>=end)return toast('Place the playhead before the sequence end.');checkpoint();timeline.titles||=[];timeline.titles.push({text:'Your title',start,end:Math.min(end,start+3),x:40,y:40,size:48});render(1);};
  A.studioTimelineTitleRemove=b=>{checkpoint();timeline.titles.splice(Number(b.dataset.index),1);render(1);};
  async function saveTimeline(){const record=current();const snapshot=clone(timeline),savingScene=sceneId;const result=await call('timeline.save',{scene_id:record.scene.id,lock_version:record.scene.lock_version,timeline:snapshot});record.scene.lock_version=result.lock_version;record.scene.settings.timeline=clone(result.timeline);if(sceneId===savingScene&&JSON.stringify(timeline)===JSON.stringify(snapshot)){timeline=clone(result.timeline);timelineDrafts.delete(savingScene);}return result;}
  A.studioTimelineSave=()=>run(async()=>{await saveTimeline();toast('Timeline saved');});
  A.studioTimelineQuote=()=>run(async()=>{const record=current();await saveTimeline();const result=await call('timeline.quote',{scene_id:record.scene.id});if(current()?.scene.id!==record.scene.id)return;LightekStudioApp.setQuote(result);if(window.LightekStudioProduction)LightekStudioProduction.go('deliver');else{ST.workspaceMode='publish';render(1);}});
  app.addEventListener('change',e=>{
    const el=e.target;if(el.matches('[data-library-scene]')){const select=el.closest('form').querySelector('[data-library-object]');if(select)select.innerHTML=objectOptions(el.value,el.closest('form').dataset.key?.startsWith('mat_')?'materials':null);}
    if(el.hasAttribute('data-timeline-playhead')){stopPreview();edit.playhead=snap(Number(el.value));render(1);A.studioTimelinePreview(true);return;}
    if(el.dataset.timelineSetting){checkpoint();timeline[el.dataset.timelineSetting]=['output','export_preset'].includes(el.dataset.timelineSetting)?el.value:Number(el.value);render(1);}
    if(el.dataset.clipField){checkpoint();timeline.clips[Number(el.dataset.clip)][el.dataset.clipField]=el.type==='checkbox'?el.checked:Number(el.value);render(1);}
    if(el.dataset.frameField){checkpoint();timeline.clips[Number(el.dataset.clip)].keyframes[Number(el.dataset.keyframe)][el.dataset.frameField]=Number(el.value);}
    if(el.dataset.trackField){checkpoint();trackFor(Number(el.dataset.track))[el.dataset.trackField]=el.type==='checkbox'?el.checked:el.dataset.trackField==='name'?el.value:Number(el.value);render(1);}
    if(el.dataset.titleField){checkpoint();timeline.titles[Number(el.dataset.title)][el.dataset.titleField]=el.dataset.titleField==='text'?el.value:Number(el.value);render(1);}
  });
  app.addEventListener('submit',e=>{
    const form=e.target.closest('[data-media-form]');if(!form)return;e.preventDefault();
    const action=form.dataset.mediaForm;
    if(action==='filter'){library.query=form.elements.query.value;library.category=form.elements.category.value;render(1);return;}
    if(form.dataset.busy)return;form.dataset.busy='true';const submit=form.querySelector('button:not([type="button"])');if(submit)submit.disabled=true;
    const notice=form.querySelector('[data-library-status],[data-import-status]');if(notice)notice.textContent='Working…';
    Promise.resolve().then(async()=>{
      if(window.LightekStudioProduction&&current()&&timelineDirty())await saveTimeline();
      if(action==='import'){
        const file=form.elements.file.files[0];if(!file||file.size>250*1024*1024)throw Error('Choose a file smaller than 250 MB.');
        const body=new FormData();body.append('file',file);body.append('purpose','studio_asset');
        const response=await fetch(window.LightekStudioUploadUrl||'/api/lightek/pwa/uploads',{method:'POST',credentials:'same-origin',headers:nevaeh.csrfHeaders(),body});const upload=await nevaeh.parseResponse(response);
        await call('asset.import',{signed_id:upload.signed_id,name:form.elements.name.value.trim()||file.name,request_key:form.dataset.requestKey||=crypto.randomUUID()});
        await loadAssets(true);toast('Import queued');
      }else if(action==='json-preset'){
        const mode=form.elements.mode.value,record=studioSceneRecord(Number(form.elements.scene_id?.value)),beforeIds=record?.scene.objects.map(object=>object.id)||[];
        const result=await call('blender.preset.use',{key:form.dataset.key,mode,name:form.elements.name.value,title:form.elements.name.value,scene_id:record?.scene.id,lock_version:record?.scene.lock_version,object_id:form.elements.object_id?.value||undefined,asset_id:form.elements.asset_id?.value?Number(form.elements.asset_id.value):undefined,request_key:form.dataset.requestKey||=crypto.randomUUID()});timelineDrafts.delete(result.scene_id);sceneId=null;await A.studioLoad(true);ST.workspaceMode='3d';location.hash='#/studio/'+result.scene_id;LightekStudioApp.applied?.(result,{key:form.dataset.key,preset:true,beforeIds});render(1);toast('Blender template ready');
      }else if(action==='native-template'){
        const result=await call('blender.template.use',{asset_id:Number(form.dataset.id),name:form.elements.name.value,source_scene:form.elements.source_scene.value||null,request_key:form.dataset.requestKey||=crypto.randomUUID()});timelineDrafts.delete(result.scene_id);sceneId=null;await A.studioLoad(true);ST.workspaceMode='3d';location.hash='#/studio/'+result.scene_id;render(1);toast('Native Blender production created');
      }else if(action==='publish'){
        const result=await call('asset.publish',{asset_id:Number(form.dataset.id),scene_id:Number(form.dataset.scene),spatial:form.elements.spatial.checked,spatial_rights:form.elements.spatial_rights.checked,allow_remix:form.elements.allow_remix.checked,community_slug:form.elements.community_slug.value,title:form.elements.title.value,platform:form.elements.platform.value,audience:form.elements.audience.value,publish_at:form.elements.publish_at.value?new Date(form.elements.publish_at.value).toISOString():null,request_key:form.dataset.requestKey||=crypto.randomUUID()});
        form.closest('dialog').close();toast(`Publication #${result.publication_id} queued`);
      }else{
        const record=studioSceneRecord(Number(form.elements.scene_id.value));if(!record)throw Error('Choose a saved scene first.');
        const payload={asset_id:Number(form.dataset.id),scene_id:record.scene.id,lock_version:record.scene.lock_version,request_key:form.dataset.requestKey||=crypto.randomUUID()};
        if(action==='camera-create')Object.assign(payload,{preset:form.dataset.preset,name:form.elements.name.value});
        if(action==='place')payload.category=form.elements.category.value;
        if(action==='use')payload.placement=form.elements.placement.value;
        if(action==='builtin')Object.assign(payload,{key:form.dataset.key,object_id:form.elements.object_id?.value,title:form.elements.title?.value,subtitle:form.elements.subtitle?.value});
        const result=await call(action==='camera-create'?'blender.camera.create':action==='builtin'?'library.apply':action==='place'?'asset.place':'asset.use',payload);
        if(result.object_id||result.object_ids?.length)ST.selectedObjectId=result.object_id||result.object_ids[0];
        sceneId=null;await A.studioLoad(true);await loadAssets(true);if(action==='camera-create')ST.workspaceMode='visual';else if(action==='use'||(result.asset_ids?.length&&!result.object_ids?.length))ST.workspaceMode='timeline';else ST.workspaceMode='3d';location.hash='#/studio/'+result.scene_id+(window.LightekStudioProduction?'/'+({visual:'camera',timeline:'edit','3d':'stage'}[ST.workspaceMode]||'stage'):'');LightekStudioApp.applied?.(result,{key:form.dataset.key,mode:ST.workspaceMode});render(1);toast('Library item ready in your production');
      }
    }).catch(error=>{if(notice)notice.textContent=error.message;toast(error.message);}).finally(()=>{delete form.dataset.busy;if(submit)submit.disabled=false;});
  });
  function stopPreview(){if(!preview)return;const state=preview;preview=null;cancelAnimationFrame(state.frame);state.items.forEach(item=>{item.el.pause?.();item.el.removeAttribute('src');item.el.load?.();});state.audio.close().catch(()=>{});window.dispatchEvent(new CustomEvent('lightek:timeline-stopped'));}
  const interpolate=(frames,key,t,base)=>{if(!frames?.length)return base;const ordered=[...frames].sort((a,b)=>a.time-b.time);if(t<=ordered[0].time)return ordered[0][key];for(let i=1;i<ordered.length;i++)if(t<ordered[i].time){const a=ordered[i-1],b=ordered[i],ratio=(t-a.time)/(b.time-a.time);return a[key]+(b[key]-a[key])*ratio;}return ordered.at(-1)[key];};
  A.studioTimelineStop=stopPreview;
  A.studioTimelinePreview=singleFrame=>run(async()=>{
    singleFrame=singleFrame===true;
    stopPreview();const canvas=app.querySelector('[data-timeline-preview]');if(!canvas||!timeline.clips.length)return;
    const audio=new AudioContext();await audio.resume();const items=[],state={audio,items,frame:0,canvas,singleFrame};preview=state;
    const offset=edit.playhead>=sequenceDuration()?0:edit.playhead;
    try{
      for(const clip of [...timeline.clips].sort((a,b)=>a.track-b.track||a.start-b.start)){
        if(singleFrame&&(offset<clip.start||offset>=clip.start+lengthOf(clip)))continue;
        if(preview!==state)return;
        const asset=library.items.find(a=>a.id===clip.asset_id);if(!asset)throw Error('Reload the media library first.');
        const el=document.createElement(asset.kind==='image'?'img':asset.kind==='audio'?'audio':'video');el.preload='auto';el.playsInline=true;
        let gain=null;const track=(timeline.tracks||[]).find(t=>t.id===clip.track)||{gain:1,pan:0};
        if(asset.kind!=='image'){
          gain=audio.createGain();const panner=audio.createStereoPanner();panner.pan.value=track.pan||0;
          const source=audio.createMediaElementSource(el),filter=audio.createBiquadFilter();filter.type='highpass';filter.frequency.value=clip.highpass||0;source.connect(filter);filter.connect(gain);gain.connect(panner);panner.connect(audio.destination);el.playbackRate=clip.speed||1;el.preservesPitch=true;
        }
        items.push({clip,asset,el,gain,track,playing:false});
        await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('Media preview timed out. Try reloading the library.')),8000);const done=error=>{clearTimeout(timer);el.onload=el.onloadeddata=el.onerror=null;error?reject(error):resolve();};el.onload=()=>done();el.onloadeddata=()=>done();el.onerror=()=>done(Error('Could not load preview media.'));el.src=asset.proxy_url;});
        if(preview!==state)return;
        if(asset.kind!=='image'&&offset>=clip.start&&offset<clip.start+lengthOf(clip)){
          const target=clip.in+(offset-clip.start)*(clip.speed||1);
          if(Math.abs(el.currentTime-target)>0.001)await new Promise(resolve=>{const timer=setTimeout(resolve,1500);el.onseeked=()=>{clearTimeout(timer);el.onseeked=null;resolve();};el.currentTime=target;});
        }
      }
      const start=performance.now(),ctx=canvas.getContext('2d'),solo=(timeline.tracks||[]).some(t=>t.solo);
      function draw(){
        if(preview!==state)return;if(!canvas.isConnected){stopPreview();return;}
        const t=singleFrame?offset:offset+(performance.now()-start)/1000;edit.playhead=Math.min(t,sequenceDuration());ctx.fillStyle='black';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.save();ctx.scale(canvas.width/timeline.width,canvas.height/timeline.height);
        for(const item of items){
          const {clip,el,asset,gain,track}=item,length=lengthOf(clip),local=t-clip.start;
          if(local<0||local>=length){if(item.playing){el.pause?.();item.playing=false;}continue;}
          if(asset.kind!=='image'&&!item.playing&&!singleFrame){el.currentTime=clip.in+local*(clip.speed||1);el.play().catch(error=>{const notice=app.querySelector('[data-timeline-status]');if(notice)notice.textContent=error.message;});item.playing=true;}
          const fade=Math.min(1,clip.fade_in?local/clip.fade_in:1,clip.fade_out?(length-local)/clip.fade_out:1);
          if(gain)gain.gain.setValueAtTime(clip.muted||track.muted||(solo&&!track.solo)?0:interpolate(clip.keyframes,'gain',local,clip.gain??1)*(track.gain??1)*fade,audio.currentTime);
          const w=el.videoWidth||el.naturalWidth,h=el.videoHeight||el.naturalHeight;
          if(w&&h){const scale=Math.min(timeline.width/w,timeline.height/h)*(clip.scale||1);ctx.save();ctx.globalAlpha=(clip.opacity??1)*fade;ctx.filter=`brightness(${Math.max(0,1+(clip.brightness||0))}) contrast(${clip.contrast??1}) saturate(${clip.saturation??1})`;ctx.drawImage(el,interpolate(clip.keyframes,'x',local,clip.x||0),interpolate(clip.keyframes,'y',local,clip.y||0),w*scale,h*scale);ctx.restore();}
        }
        if(timeline.output!=='audio')for(const title of timeline.titles||[]){if(t<title.start||t>title.end)continue;ctx.save();ctx.font=`${title.size}px sans-serif`;ctx.textBaseline='top';title.text.split('\n').forEach((line,index)=>{const y=title.y+index*title.size*1.2;ctx.fillStyle='#0008';ctx.fillRect(title.x-10,y-10,ctx.measureText(line).width+20,title.size*1.2+10);ctx.fillStyle='white';ctx.fillText(line,title.x,y);});ctx.restore();}
        ctx.restore();const notice=app.querySelector('[data-timeline-status]');if(notice)notice.textContent=t.toFixed(3)+' seconds · proxy preview; export applies final processing';
        const playhead=app.querySelector('[data-timeline-playhead],[data-vw-playhead]');if(playhead)playhead.value=edit.playhead;window.dispatchEvent(new CustomEvent('lightek:timeline-time',{detail:{time:edit.playhead}}));const clock=app.querySelector('[data-vw-time]');if(clock)clock.textContent=Math.floor(edit.playhead/60).toString().padStart(2,'0')+':'+(edit.playhead%60).toFixed(1).padStart(4,'0');
        if(singleFrame||t>=sequenceDuration()){stopPreview();return;}state.frame=requestAnimationFrame(draw);
      }draw();
    }catch(error){if(preview===state)stopPreview();throw error;}
  });
  new MutationObserver(()=>{if(preview&&!preview.canvas?.isConnected)stopPreview();}).observe(app,{childList:true,subtree:true});
  const timelineDirty=()=>!!timeline&&JSON.stringify(timeline)!==JSON.stringify(current()?.scene.settings.timeline||{output:'video',width:1280,height:720,clips:[]});
  window.LightekStudioTimeline={
    editor:()=>({nextBefore:library.nextBefore,selected:edit.selected,playhead:edit.playhead,undo:edit.undo.length,redo:edit.redo.length,assets:clone(library.items),loading:library.loading,error:library.error}),
    insert:(id,start,track,range={})=>{
      const asset=library.items.find(a=>a.id===Number(id)&&a.status==='ready'&&['image','video','audio'].includes(a.kind));
      if(!asset)throw Error('Choose prepared video, audio or an image.');
      if(timeline.clips.length>=64)throw Error('This sequence supports up to 64 clips.');
      const sourceEnd=Math.min(Number(asset.metadata?.duration)||5,600);
      const first=Number(range.in??0),last=Number(range.out??sourceEnd);
      const lane=track??(asset.kind==='audio'?1:0);
      const ending=Math.max(0,...timeline.clips.filter(c=>c.track===lane).map(c=>c.start+lengthOf(c)));
      const at=snap(start??ending);
      if(!Number.isFinite(first)||!Number.isFinite(last)||first<0||last<=first||last>sourceEnd+.001)throw Error('Choose an out point after the in point within this source.');
      if(at+last-first>600)throw Error('This sequence supports ten minutes. Trim the source or use a shorter range.');
      checkpoint();timeline.clips.push({asset_id:asset.id,in:first,out:last,start:at,track:lane,gain:1,x:0,y:0,muted:false,keyframes:[]});
      edit.selected=timeline.clips.length-1;edit.playhead=at;render(1);
    },
    trim:(index,edge,seconds)=>{
      const clip=timeline.clips[index];if(!clip)return;
      const asset=library.items.find(a=>a.id===clip.asset_id),speed=clip.speed||1,frame=1/(timeline.fps||24);
      const next=clone(clip),oldLength=lengthOf(clip);
      if(edge==='in'){
        const shift=snap(Math.max(-clip.in/speed,-clip.start,Math.min(oldLength-frame,seconds)));
        next.in=clip.in+shift*speed;next.start=clip.start+shift;
        next.keyframes=(clip.keyframes||[]).map(f=>({...f,time:f.time-shift})).filter(f=>f.time>=0&&f.time<=oldLength-shift);
      }else{
        const maxSource=Math.min(600,Number(asset?.metadata?.duration)||600);
        next.out=Math.max(clip.in+frame*speed,Math.min(maxSource,clip.out+snap(seconds)*speed,clip.in+(600-clip.start)*speed));
        next.keyframes=(clip.keyframes||[]).filter(f=>f.time<=(next.out-next.in)/speed);
      }
      const len=lengthOf(next);next.fade_in=Math.min(next.fade_in||0,len);next.fade_out=Math.min(next.fade_out||0,len);
      checkpoint();Object.assign(clip,next);edit.selected=index;edit.playhead=clip.start;render(1);
    },
    move:(index,start,track)=>{if(!timeline.clips[index])return;if(start+lengthOf(timeline.clips[index])>600)throw Error('This sequence supports ten minutes.');checkpoint();Object.assign(timeline.clips[index],{start:snap(Math.max(0,start)),track:Math.max(0,Math.min(15,Number(track)))});edit.selected=index;render(1);},
    playhead:seconds=>{stopPreview();edit.playhead=snap(Math.max(0,Number(seconds)||0));},
    playing:()=>!!preview&&!preview.singleFrame,
    time:()=>edit.playhead,dirty:timelineDirty,hasDrafts:()=>timelineDirty()||[...timelineDrafts.entries()].some(([id,d])=>JSON.stringify(d.timeline)!==JSON.stringify(studioSceneRecord(id)?.scene.settings.timeline||{output:'video',width:1280,height:720,clips:[]})),
    get:()=>timeline?JSON.parse(JSON.stringify(timeline)):null,
    set:value=>{stopPreview();timeline=JSON.parse(JSON.stringify(value));},
    configure:attributes=>{checkpoint();Object.assign(timeline,attributes);},
    save:saveTimeline,
    assets:items=>{library.items=[...items,...library.items.filter(a=>!items.some(b=>b.id===a.id))];},
    seek:seconds=>{edit.playhead=Number(seconds)||0;return A.studioTimelinePreview(true);},
    play:seconds=>{edit.playhead=Number(seconds)||0;return A.studioTimelinePreview();},
    stop:stopPreview
  };

})();
