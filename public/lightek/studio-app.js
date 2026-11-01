/* Persisted authoring controls over the existing Studio workspace. */
(() => {
  let currentScene = null;
  let operationRows = [];
  let publicationRows = [];
  let operationProject = null;
  let operationBusy = false;
  let quote = null;
  let dirty = false;
  const input = (name, label, value, type = 'text') => `<label class="fld"><span>${E(label)}</span><input name="${E(name)}" type="${type}" ${type === "number" ? 'step="any" required' : ''} value="${E(String(value ?? ''))}"></label>`;
  const button = (label, action, attrs = '') => `<button type="button" class="btn sm" data-a="${action}" ${attrs} ${ST.busy ? 'disabled' : ''}>${E(label)}</button>`;
  const current = () => studioSceneRecord(studioCurrentSceneId());
  function prepare(record) {
    if (currentScene === record.scene.id) return;
    currentScene = record.scene.id;
    const workspace = record.scene.settings?.workspace || {};
    Object.assign(STUDIO_WAVE2_STATE, { scriptDraft: '', beats: [], checks: [], muted: [], storyboard: [] }, workspace.story || {});
    if (workspace.visual) Object.assign(STUDIO_V3_STATE, workspace.visual);
    if (workspace.delivery) Object.assign(STUDIO_W4_STATE, workspace.delivery);
    if (workspace.layout) Object.assign(STUDIO_WORKSPACE_LAYOUT, workspace.layout);
    STUDIO_W5_STATE.presets = workspace.presets || [];
    dirty = false;
    operationRows = []; publicationRows = []; operationProject = null; quote = null;
  }
  function inspector(scene) {
    const object = studioWorkspaceSelectedObject(scene);
    if (!object) return `<aside class="studio-workspace-inspector-shell"><h3>Inspector</h3><p>Select a scene element to edit its saved properties.</p><a class="btn sm" href="#/studio/${scene.id}" data-a="studioWorkspaceMode" data-mode="3d">Open scene editor</a></aside>`;
    const definition = object.definition || {};
    return `<aside class="studio-workspace-inspector-shell"><span class="eb">Contextual Inspector</span><h3>${E(object.name)}</h3><form data-studio-form="inspector" data-scene="${scene.id}" data-object="${object.id}">${input('name', 'Display name', object.name)}${['location', 'rotation', 'scale'].map(key => `<fieldset style="border:0;padding:0"><legend>${E(key.charAt(0).toUpperCase() + key.slice(1))}</legend><div class="pwa-vector">${['X', 'Y', 'Z'].map((axis, i) => input(`${key}_${i}`, axis, definition[key]?.[i] ?? (key === 'scale' ? 1 : 0), 'number')).join('')}</div></fieldset>`).join('')}<button class="btn p sm" ${ST.busy ? 'disabled' : ''}>Save element</button></form><p>Changes update the scene graph and viewport.</p></aside>`;
  }
  function story(record, mode) {
    if (!['script', 'storyboard', 'audio', 'planning'].includes(mode)) return null;
    const state = STUDIO_WAVE2_STATE;
    if (mode === 'script') return `<section class="studio-wave2"><span class="eb">Story & Production</span><h2>Script</h2><label class="fld"><span>${E(record.scene.name)} · Scene script</span><textarea data-studio-script rows="18" placeholder="Write the scene…">${E(state.scriptDraft)}</textarea></label><p>Save workspace to persist your script with this scene.</p></section>`;
    if (mode === 'storyboard') return `<section class="studio-wave2"><span class="eb">Story & Production</span><h2>Storyboard</h2><div class="g2">${(state.storyboard || []).map((shot, i) => `<div class="studio-wave2-panel"><h3>Shot ${i + 1}</h3><label class="fld"><span>Framing & action</span><textarea data-studio-shot="${i}" rows="5">${E(shot)}</textarea></label>${button('Remove shot', 'studioShotRemove', `data-index="${i}"`)}</div>`).join('')}</div>${button('Add shot', 'studioShotAdd')}</section>`;
    if (mode === 'planning') return `<section class="studio-wave2"><span class="eb">Production Planning</span><h2>Readiness</h2>${STUDIO_WAVE2_TASKS.map((task, i) => `<label class="studio-wave2-check"><input type="checkbox" data-studio-wave2-task="${i}" ${state.checks.includes(i) ? 'checked' : ''}><span>${E(task)}</span></label>`).join('')}<p>Readiness is saved with the scene.</p></section>`;
    return `<section class="studio-wave2"><span class="eb">Audio</span><h2>Scene sound</h2><p>Publish or upload audio through Create, then reference its post ID in your scene notes.</p><label class="fld"><span>Dialogue, ambience, music & cues</span><textarea data-studio-audio rows="10">${E(state.audioNotes || '')}</textarea></label><a class="btn sm" href="#/create/audio">Upload audio</a></section>`;
  }
  const hexColor = values => '#' + (values || [0.55,0.58,0.65]).slice(0,3).map(v => Math.round(Math.max(0,Math.min(1,Number(v))) * 255).toString(16).padStart(2,'0')).join('');
  function cameraForm(record, object){
    const d=object.definition||{},select=(name,label,choices,value)=>`<label class="fld"><span>${E(label)}</span><select name="${name}">${choices.map(([key,text])=>`<option value="${key}" ${value===key?'selected':''}>${E(text)}</option>`).join('')}</select></label>`;
    const active=Number(record.scene.settings?.active_camera_object_id)===object.id||record.scene.settings?.active_camera===(d.blender_object_name||object.name);
    return `<section class="studio-v3-card"><span class="eb">Native Blender camera</span><h3>${E(object.name)}</h3><p>These settings drive the Blender camera used for rendering. Panoramic cameras use Cycles.</p><form data-studio-form="camera"><div class="pwa-editor-fields">${select('camera_type','Projection',[['PERSP','Perspective'],['ORTHO','Orthographic'],['PANO','Panoramic']],d.camera_type||'PERSP')}${select('lens_unit','Lens unit',[['MILLIMETERS','Millimeters'],['FOV','Field of view']],d.lens_unit||'MILLIMETERS')}${input('lens','Focal length · mm',d.lens??50,'number')}${input('fov_degrees','Field of view · degrees',d.fov_degrees??39.5978,'number')}${select('sensor_fit','Sensor fit',[['AUTO','Auto'],['HORIZONTAL','Horizontal'],['VERTICAL','Vertical']],d.sensor_fit||'AUTO')}${input('sensor_width','Sensor width · mm',d.sensor_width??36,'number')}${input('sensor_height','Sensor height · mm',d.sensor_height??24,'number')}${input('shift_x','Horizontal lens shift',d.shift_x??0,'number')}${input('shift_y','Vertical lens shift',d.shift_y??0,'number')}${input('clip_start','Near clip',d.clip_start??0.1,'number')}${input('clip_end','Far clip',d.clip_end??1000,'number')}${input('ortho_scale','Orthographic scale',d.ortho_scale??6,'number')}${select('panorama_type','Panoramic projection',[['EQUIRECTANGULAR','Equirectangular'],['EQUIANGULAR_CUBEMAP_FACE','Equiangular cubemap face'],['FISHEYE_LENS_POLYNOMIAL','Fisheye lens polynomial'],['FISHEYE_EQUIDISTANT','Fisheye equidistant'],['FISHEYE_EQUISOLID','Fisheye equisolid'],['MIRRORBALL','Mirror ball']],d.panorama_type||'EQUIRECTANGULAR')}${input('fisheye_fov','Fisheye field of view · degrees',d.fisheye_fov??180,'number')}${input('fisheye_lens','Fisheye lens · mm',d.fisheye_lens??10.5,'number')}</div><details><summary>Panoramic crop & lens calibration</summary><div class="pwa-editor-fields">${input('latitude_min','Latitude minimum · degrees',d.latitude_min??-90,'number')}${input('latitude_max','Latitude maximum · degrees',d.latitude_max??90,'number')}${input('longitude_min','Longitude minimum · degrees',d.longitude_min??-180,'number')}${input('longitude_max','Longitude maximum · degrees',d.longitude_max??180,'number')}${[0,1,2,3,4].map(index=>input(`fisheye_polynomial_k${index}`,`Fisheye polynomial K${index}`,d[`fisheye_polynomial_k${index}`]??[-0.0000117351437,-0.0199887361,-0.00000335253,0.00000309928,-0.0000000260646][index],'number')).join('')}</div></details><details><summary>Stereo camera · native multiview scenes</summary><div class="pwa-editor-fields">${select('stereo_convergence_mode','Stereo convergence',[['OFFAXIS','Off-axis'],['PARALLEL','Parallel'],['TOE','Toe-in']],d.stereo_convergence_mode||'OFFAXIS')}${select('stereo_pivot','Stereo pivot',[['LEFT','Left'],['RIGHT','Right'],['CENTER','Center']],d.stereo_pivot||'LEFT')}${input('stereo_interocular_distance','Interocular distance',d.stereo_interocular_distance??0.065,'number')}${input('stereo_convergence_distance','Convergence distance',d.stereo_convergence_distance??1.95,'number')}</div></details><fieldset><legend>Depth of field</legend><label><input type="checkbox" name="dof_enabled" ${d.dof_enabled?'checked':''}> Enable depth of field</label><div class="pwa-editor-fields">${input('focus_distance','Focus distance',d.focus_distance??10,'number')}${input('focus_object_name','Native focus object · optional',d.focus_object_name||'')}${input('aperture_fstop','Aperture · f-stop',d.aperture_fstop??2.8,'number')}${input('aperture_blades','Aperture blades · 0 or 3–16',d.aperture_blades??0,'number')}${input('aperture_rotation','Aperture rotation · degrees',d.aperture_rotation??0,'number')}${input('aperture_ratio','Anamorphic aperture ratio',d.aperture_ratio??1,'number')}</div></fieldset><label><input type="checkbox" name="active" ${active?'checked':''}> Use as active Blender render camera</label><button class="btn p">Save Blender camera</button><p role="status" data-camera-status></p></form><button type="button" class="btn sm" data-a="studioCameraRenderQuote">Render active Blender camera</button><p>Review the render quote and continue through the existing render checkout.</p></section>`;
  }
  function visual(record) {
    const scene = record.scene, object = studioWorkspaceSelectedObject(scene), settings = scene.settings || {}, d = object?.definition || {};
    return `<section class="studio-v3"><span class="eb">Visual Production</span><h2>Craft the image.</h2><div class="pwa-post-actions">${(scene.objects||[]).filter(item=>item.object_type==='camera').map(camera=>button(`Edit ${camera.name}`,'studioSelectObject',`data-id="${camera.id}"`)).join('')}</div><form data-studio-form="visual"><div class="studio-v3-grid"><section class="studio-v3-card"><h3>Render settings</h3><label class="fld"><span>Render engine</span><select name="render_engine"><option value="BLENDER_EEVEE_NEXT" ${settings.render_engine==='BLENDER_EEVEE_NEXT'?'selected':''}>Eevee</option><option value="CYCLES" ${settings.render_engine==='CYCLES'?'selected':''}>Cycles</option></select></label>${input('resolution_x','Width',settings.resolution_x || 1280,'number')}${input('resolution_y','Height',settings.resolution_y || 720,'number')}${input('frame_start','Start frame',settings.frame_start??1,'number')}${input('frame_end','End frame',settings.frame_end??250,'number')}${input('frame_current','Render frame',settings.frame_current??1,'number')}${input('fps','Frames per second',settings.fps??24,'number')}${input('samples','Cycles preview samples',settings.samples??32,'number')}<label class="fld"><span>Background</span><select name="transparent_background"><option value="false">Scene world</option><option value="true" ${settings.transparent_background?'selected':''}>Transparent</option></select></label></section><section class="studio-v3-card"><h3>${E(object?.name || 'Select a scene element')}</h3>${object?.object_type==='native_object'?'<p>Edit this native object in the Blender Inspector.</p>':object?.object_type==='camera'?'<p>Edit the native Blender camera in the panel below.</p>':object?.object_type.endsWith('_light')?input('energy','Light energy',d.energy ?? (object.object_type==='sun_light'?3:1000),'number')+input('color','Light color',hexColor(d.color || [1,1,1]),'color')+(object.object_type==='area_light'?input('size','Light size',d.size || 5,'number'):''):object?input('color','Material color',hexColor(d.material?.color),'color'):'<p>Select a camera, light or object from the scene graph.</p>'}</section></div><button class="btn p" ${ST.busy?'disabled':''}>Save visual settings</button><p>Saved values are used by the render manifest.</p></form>${object?.object_type==='camera'?cameraForm(record,object):''}</section>`;
  }
  function delivery(record, mode) {
    if (!['publish', 'distribution', 'release', 'live'].includes(mode)) return null;
    if (mode === 'live') return `<section class="studio-w4"><span class="eb">Delivery & Broadcast</span><h2>Control the show.</h2><p>Open Lightek's live studio to connect your camera, screen, audio and streaming destination.</p><a class="btn p" href="/dashboard/live">Open Live Studio</a></section>`;
    return `<section class="studio-w4"><span class="eb">Delivery & Broadcast</span><h2>${mode === 'release' ? 'Plan the launch.' : mode === 'distribution' ? 'Reach the audience.' : 'Prepare the master.'}</h2><div class="studio-w4-grid"><div class="studio-w4-panel"><h3>Render & artifacts</h3><p>Request a render quote, review its price, then continue to payment. Completed artifacts appear below.</p>${button('Get render quote', 'studioRenderQuote')}${quote ? `<div class="pwa-empty"><p>${E(new Intl.NumberFormat(undefined,{style:"currency",currency:"USD"}).format(Number(quote.quote.total_cents||0)/100))} total · includes processing and network fees</p>${button('Continue to payment', 'studioRenderCheckout')}</div>` : ''}${button('Refresh operations', 'studioOperationsLoad')}<div>${operationRows.map(op => `<article class="pwa-post"><b>${E(op.type)} #${op.id} · ${E(op.status)}</b>${op.error ? `<p role="alert">${E(op.error)}</p>` : ''}${op.artifacts.map(artifact => `<p><a href="${E(artifact.url)}" target="_blank" rel="noopener">${E(artifact.filename)}</a> ${["preview","image","video","audio"].includes(artifact.kind)?button("Publish / schedule", "studioArtifactPublish", `data-artifact="${artifact.id}" data-project="${record.project.id}"`):""}</p>`).join('')}</article>`).join('') || '<p>No operations loaded yet.</p>'}</div></div><div class="studio-w4-panel"><h3>Publications</h3>${publicationRows.map(p=>`<article class="pwa-post"><b>#${p.id} · ${E(p.status)}</b>${p.scheduled_at?`<p>${E(new Date(p.scheduled_at).toLocaleString())}</p>`:""}${p.error?`<p role="alert">${E(p.error)}</p>`:""}${p.post_id?`<a class="btn sm" href="#/post/${Number(p.post_id)}">View published post</a>`:""}</article>`).join("") || "<p>No publications loaded yet.</p>"}<h3>Release notes</h3><label class="fld"><span>Release date</span><input type="date" data-studio-release-date value="${E(STUDIO_W4_STATE.releaseDate || '')}"></label><label class="fld"><span>Distribution & launch plan</span><textarea rows="12" data-studio-release-notes>${E(STUDIO_W4_STATE.notes || '')}</textarea></label><p>Save workspace to persist your plan. Publishing and scheduling require a selected completed artifact.</p><a class="btn sm" href="#/create">Publish to Lightek</a></div></div></section>`;
  }
  function director(record) {
    return `<section class="studio-workspace-director"><span class="eb">Nevaeh Director</span><h3>Direct the scene.</h3><p>Available procedures: add a cube, sphere, cylinder, plane, camera or light; duplicate or delete the selected element; move, rotate or scale it.</p><form data-studio-form="director"><label class="fld"><span>Direction</span><input name="instruction" required maxlength="2000" placeholder="Add a camera named Main Camera"></label><button class="btn p sm" ${ST.busy ? 'disabled' : ''}>Execute direction</button></form><p>Directions pass through Nevaeh and Gatekeeper. Unsupported requests follow Nevaeh's escalation procedure.</p></section>`;
  }
  function tools(record) {
    return `<div class="pwa-post-actions"><span role="status" id="studio-save-status">${dirty ? 'Unsaved changes' : 'Workspace loaded'}</span>${button('Save workspace', 'studioWorkspaceSave')}${button('Save as template', 'studioTemplatePersist', `data-project="${record.project.id}"`)}${button('Delete project', 'studioProjectDelete', `data-project="${record.project.id}"`)}</div>`;
  }
  async function execute(capability, payload) {
    if (ST.busy) return null;
    ST.busy = true;
    try { const r = await nevaeh.execute({ capability, payload }); return r.result; }
    finally { ST.busy = false; }
  }
  const run = fn => Promise.resolve().then(fn).catch(error => toast(error.message));
  A.studioWorkspaceSave = () => run(async () => {
    const record = current();
    if (!record) return;
    const result = await execute('studio.workspace.scene.save', { scene_id: record.scene.id, lock_version: record.scene.lock_version,
      workspace: { story: STUDIO_WAVE2_STATE, visual: STUDIO_V3_STATE, delivery: STUDIO_W4_STATE, layout: STUDIO_WORKSPACE_LAYOUT, presets: STUDIO_W5_STATE.presets } });
    if (!result) return;
    record.scene.lock_version = result.lock_version;
    record.scene.settings.workspace = result.workspace;
    dirty = false;
    const status = document.getElementById('studio-save-status'); if (status) status.textContent = 'Saved to your account';
  });
  A.studioShotAdd = () => { STUDIO_WAVE2_STATE.storyboard ||= []; STUDIO_WAVE2_STATE.storyboard.push(''); dirty = true; render(1); };
  A.studioShotRemove = b => { STUDIO_WAVE2_STATE.storyboard.splice(Number(b.dataset.index), 1); dirty = true; render(1); };
  A.studioProjectDelete = b => run(async () => { if (!confirm('Delete this project, its scenes and artifacts?')) return; await execute('studio.workspace.project.delete', { project_id: Number(b.dataset.project) }); location.hash = '#/studio'; await A.studioLoad(true); });
  A.studioTemplatePersist = b => run(async () => {
    const name = prompt('Template name', current()?.project.name || 'Studio template'); if (!name?.trim()) return;
    const result = await execute('studio.workspace.template.save', { project_id: Number(b.dataset.project), name: name.trim(), request_key: crypto.randomUUID() });
    if (result) { toast('Template saved'); await A.studioLoad(true); }
  });
  A.studioTemplateUsePersisted = b => run(async () => {
    const result = await execute('studio.workspace.template.use', { project_id: Number(b.dataset.project), request_key: crypto.randomUUID() });
    if (result) { await A.studioLoad(true); location.hash = `#/studio/${result.scene_id}`; }
  });
  A.studioRenderQuote = () => run(async () => { const record = current(); quote = await execute('studio.workspace.render.quote', { scene_id: record.scene.id }); render(1); });
  A.studioCameraRenderQuote=()=>run(async()=>{await A.studioRenderQuote();ST.workspaceMode='publish';render(1);});
  A.studioRenderCheckout = () => run(async () => {
    if (!quote) return;
    const result = await execute('studio.workspace.render.checkout', { operation_id: quote.operation_id });
    if (result?.checkout_url) { const url = new URL(result.checkout_url); if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com') throw new Error('Invalid checkout URL'); location.assign(url.href); }
  });
  A.studioArtifactPublish = b => {
    const dialog = document.createElement('dialog');
    dialog.className = 'pwa-publish-dialog';
    dialog.innerHTML = `<form data-studio-form="publication" data-project="${Number(b.dataset.project)}" data-artifact="${Number(b.dataset.artifact)}" data-scene="${Number(current()?.scene.id)}"><h2>Publish to Lightek</h2><label class="fld"><span>Title</span><input name="title" required maxlength="160" value="${E(current()?.project.name || '')}"></label><label class="fld"><span>Destination</span><select name="platform"><option value="lightek_social">Lightek community & profile</option><option value="lightek_streaming">Lightek OTT</option><option value="octavia">Octavia</option></select></label><label class="fld"><span>Audience</span><select name="audience"><option value="everyone">Everyone</option><option value="women">Women only</option><option value="men">Men only</option></select></label><label class="fld"><span>Description</span><textarea name="content" rows="4" maxlength="50000"></textarea></label><label class="fld"><span>Community slug · optional</span><input name="community_slug" maxlength="100"></label><label><input type="checkbox" name="spatial"> Include current interactive scene · Lightek social</label><label><input type="checkbox" name="spatial_rights"> I have permission to share the included 3D assets</label><label><input type="checkbox" name="allow_remix"> Allow Fork Scene and asset reuse under CC-BY-4.0</label><label class="fld"><span>Release time · leave empty to publish now</span><input type="datetime-local" name="publish_at"></label><div class="pwa-post-actions"><button class="btn p">Queue publication</button><button type="button" class="btn" data-close-publication>Cancel</button></div><p role="status" data-publication-status></p></form>`;
    dialog.querySelector('[data-close-publication]').onclick = () => dialog.close();
    dialog.addEventListener('close',()=>dialog.remove());
    app.append(dialog);dialog.showModal();
  };
  A.studioOperationsLoad = () => run(async () => {
    const record = current(); if (!record || operationBusy) return;
    operationBusy = true;
    try { const result = await execute('studio.workspace.operations.list', { project_id: record.project.id }); if (result) { operationRows = result.operations; publicationRows = result.publications || []; operationProject = record.project.id; render(1); } }
    finally { operationBusy = false; }
  });
  app.addEventListener('input', event => {
    const el = event.target;
    if (el.matches('[data-studio-script]')) STUDIO_WAVE2_STATE.scriptDraft = el.value;
    else if (el.matches('[data-studio-shot]')) STUDIO_WAVE2_STATE.storyboard[Number(el.dataset.studioShot)] = el.value;
    else if (el.matches('[data-studio-audio]')) STUDIO_WAVE2_STATE.audioNotes = el.value;
    else if (el.matches('[data-studio-release-date]')) STUDIO_W4_STATE.releaseDate = el.value;
    else if (el.matches('[data-studio-release-notes]')) STUDIO_W4_STATE.notes = el.value;
    else if (el.closest('[data-studio-form], [data-native-object-form], [data-media-form]') || el.matches('[data-blender-preview-frame], #studio-create-name, #studio-create-type')) return;
    else if (!el.closest('.studio-shell')) return;
    dirty = true;
    const status = document.getElementById('studio-save-status'); if (status) status.textContent = 'Unsaved changes';
  });
  app.addEventListener('submit', event => {
    const camera=event.target.closest('[data-studio-form="camera"]');
    if(camera){event.preventDefault();const notice=camera.querySelector('[data-camera-status]');run(async()=>{
      const values=Object.fromEntries(new FormData(camera)),record=current(),object=studioWorkspaceSelectedObject(record.scene);
      values.dof_enabled=camera.elements.dof_enabled.checked;const active=camera.elements.active.checked;delete values.active;
      const result=await execute('studio.workspace.blender.camera.save',{scene_id:record.scene.id,object_id:object.id,lock_version:record.scene.lock_version,properties:values,active});
      if(result){notice.textContent='Blender camera saved';await A.studioLoad(true);toast('Blender camera saved');}
    });return;}
    const visualForm = event.target.closest('[data-studio-form="visual"]');
    if (visualForm) {
      event.preventDefault();
      const data = Object.fromEntries(new FormData(visualForm));
      run(async()=>{
        const record = current(), object = studioWorkspaceSelectedObject(record.scene);
        const rgb = data.color ? [1,3,5].map(start => parseInt(data.color.slice(start,start+2),16)/255) : null;
        const result = await execute('studio.workspace.visual.save', {scene_id:record.scene.id,lock_version:record.scene.lock_version,object_id:['camera','native_object'].includes(object?.object_type)?null:object?.id,
          render_settings:{render_engine:data.render_engine,resolution_x:Number(data.resolution_x),resolution_y:Number(data.resolution_y),transparent_background:data.transparent_background==='true',frame_start:Number(data.frame_start),frame_end:Number(data.frame_end),frame_current:Number(data.frame_current),fps:Number(data.fps),samples:Number(data.samples)},
          properties:{...Object.fromEntries(['energy','size'].filter(key=>data[key]!==undefined).map(key=>[key,Number(data[key])])),...(rgb?{color:object?.object_type.endsWith('_light')?rgb:[...rgb,1]}:{})}});
        if(result){await A.studioLoad(true);toast('Visual settings saved');}
      });
      return;
    }
    const publicationForm = event.target.closest('[data-studio-form="publication"]');
    if (publicationForm) {
      event.preventDefault();
      const values = Object.fromEntries(new FormData(publicationForm));
      run(async () => {
        const result = await execute('studio.workspace.artifact.publish', { project_id: Number(publicationForm.dataset.project), artifact_id: Number(publicationForm.dataset.artifact), scene_id:Number(publicationForm.dataset.scene),spatial:publicationForm.elements.spatial.checked,spatial_rights:publicationForm.elements.spatial_rights.checked,allow_remix:publicationForm.elements.allow_remix.checked,community_slug:values.community_slug,title: values.title, content: values.content, platform:values.platform,audience:values.audience,publish_at: values.publish_at ? new Date(values.publish_at).toISOString() : null, request_key: publicationForm.dataset.requestKey ||= crypto.randomUUID() });
        if (result) { publicationForm.closest('dialog').close(); await A.studioOperationsLoad(); toast(`Publication #${result.publication_id} queued`); }
      });
      return;
    }
    const directorForm = event.target.closest('[data-studio-form="director"]');
    if (directorForm) {
      event.preventDefault();
      run(async () => {
        const record = current();
        const selected = studioWorkspaceSelectedObject(record.scene);
        const result = await execute('studio.workspace.director.execute', { scene_id: record.scene.id, object_id: selected?.id, instruction: new FormData(directorForm).get('instruction') });
        if (result?.work_item_id) { await nevaeh.waitForExecution(result); await A.studioLoad(true); toast('Direction completed'); }
      });
      return;
    }
    const form = event.target.closest('[data-studio-form="inspector"]'); if (!form) return;
    event.preventDefault();
    run(async () => {
      const values = Object.fromEntries(new FormData(form));
      const attributes = { name: values.name };
      for (const key of ['location', 'rotation', 'scale']) {
        attributes[key] = [0, 1, 2].map(i => Number(values[`${key}_${i}`]));
        if ([0,1,2].some(i => !values[`${key}_${i}`]?.trim()) || attributes[key].some(n => !Number.isFinite(n))) throw new Error('Enter finite numbers for the transform.');
      }
      await studioExecuteMutation('studio.scene_object.transform', { scene_id: Number(form.dataset.scene), object_id: Number(form.dataset.object), attributes });
    });
  });
  const originalStudio = R.studio;
  R.studio = id => {
    if (!meProfile() || !ST.loaded || !['library', 'templates', 'template-maker', 'template-config'].includes(id)) return originalStudio(id);
    const templates = ST.projects.filter(p => p.is_template);
    const content = id === 'library' ? ST.projects.map(project => `<section class="studio-panel"><h2>${E(project.name)}</h2>${project.scenes.map(scene => `<a class="btn sm" href="#/studio/${scene.id}">${E(scene.name)} · ${scene.object_count} elements</a>`).join(' ')}</section>`).join('') : templates.map(project => `<section class="studio-panel"><h2>${E(project.name)}</h2><p>${E(project.description || '')}</p>${button('Create from template', 'studioTemplateUsePersisted', `data-project="${project.id}"`)}</section>`).join('');
    return `<div class="wrap pwa-page"><span class="eb">Lightek Studio</span><h1>${id === 'library' ? 'Library' : 'Templates'}</h1><p>${id === 'library' ? 'Saved projects, scenes and scene elements.' : 'Save a project as a template from its workspace, then create a new independent project from it.'}</p><a class="btn sm" href="#/studio">Back to Studio</a><div class="g2" style="margin-top:24px">${content || '<p>Your library is empty. Create a project to get started.</p>'}</div></div>`;
  };
  window.LightekStudioApp = { prepare, inspector, story, delivery, tools, director, visual, setQuote(value){quote=value;} };
})();
