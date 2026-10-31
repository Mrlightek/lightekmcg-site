(() => {
  const library={loaded:false,loading:false,items:[],error:''};
  let sceneId=null,timeline=null,preview=null;
  const esc=v=>E(String(v??''));
  const current=()=>studioSceneRecord(studioCurrentSceneId());
  const call=async(action,payload={})=>(await nevaeh.execute({capability:'studio.workspace.'+action,payload})).result;
  const run=fn=>Promise.resolve().then(fn).catch(error=>toast(error.message));
  const field=(label,value,attrs,type='number')=>`<label class="fld"><span>${esc(label)}</span><input type="${type}" step="any" value="${esc(value)}" ${attrs}></label>`;
  const previousPrepare=LightekStudioApp.prepare;
  LightekStudioApp.prepare=record=>{previousPrepare(record);if(sceneId!==record.scene.id){sceneId=record.scene.id;timeline=JSON.parse(JSON.stringify(record.scene.settings.timeline||{output:'video',width:1280,height:720,clips:[]}));stopPreview();}};
  async function loadAssets(force=false){
    if(library.loading||library.loaded&&!force)return;
    library.loading=true;
    try{const data=await call('assets.list');if(!Array.isArray(data.assets))throw Error('The asset library response was incomplete.');library.items=data.assets;library.loaded=true;library.error='';}
    catch(error){library.error=error.message;library.loaded=true;}
    finally{library.loading=false;if(location.hash.startsWith('#/studio'))render(1);}
    if(library.items.some(a=>a.status==='uploaded'||a.status==='processing'))setTimeout(()=>{if(location.hash.startsWith('#/studio'))loadAssets(true)},3000);
  }
  A.studioAssetsReload=()=>run(()=>loadAssets(true));
  const previousAfter=AF.studio;
  AF.studio=id=>{previousAfter(id);if(me())loadAssets();};
  const previousStudio=R.studio;
  R.studio=id=>{
    if(id!=='library'||!meProfile()||!ST.loaded)return previousStudio(id);
    return `<div class="wrap pwa-page"><span class="eb">Lightek Studio</span><h1>Asset Library</h1><p>Media, Blender scenes and GLB models, with previews and reusable scene placement.</p><a class="btn" href="#/studio">Back to productions</a><button class="btn" data-a="studioAssetsReload">Refresh library</button><form data-media-form="import" class="pwa-post"><label class="fld"><span>Name</span><input name="name" maxlength="160"></label><label class="fld"><span>Choose an image, audio, video, .blend or .glb file · up to 250 MB</span><input type="file" name="file" accept="image/*,audio/*,video/*,.blend,.glb" required></label><button class="btn p">Import asset</button><p role="status" data-import-status></p></form>${library.error?`<p role="alert">${esc(library.error)}</p>`:''}<div class="g3">${library.items.map(asset=>`<article class="pwa-post"><h3>${esc(asset.name)}</h3><p>${esc(asset.kind)} · ${esc(asset.status)}</p>${asset.error?`<p role="alert">${esc(asset.error)}</p>`:''}${asset.thumbnail_url?`<img class="pwa-media" src="${esc(asset.thumbnail_url)}" alt="">`:''}${asset.status==='ready'?['glb','blend'].includes(asset.kind)?`<button class="btn sm" data-a="studioAssetPreview" data-id="${asset.id}">3D preview</button><form data-media-form="place" data-id="${asset.id}"><label class="fld"><span>Add to scene</span><select name="scene_id">${studioSceneRecords().map(record=>`<option value="${record.scene.id}">${esc(record.project.name)} · ${esc(record.scene.name)}</option>`).join('')}</select></label><label class="fld"><span>Production role</span><select name="category">${['character','environment','prop','vehicle','architecture','geometry'].map(name=>`<option>${name}</option>`).join('')}</select></label><button class="btn sm">Place in scene</button></form>`:asset.kind==='image'?`<img class="pwa-media" src="${esc(asset.proxy_url)}" alt="${esc(asset.name)}">`:`<${asset.kind==='audio'?'audio':'video'} class="pwa-media" src="${esc(asset.proxy_url)}" controls playsinline preload="metadata"></${asset.kind==='audio'?'audio':'video'}>`:''}<div data-preview-for="${asset.id}"></div></article>`).join('')||'<p>No assets yet. Import your first file above.</p>'}</div></div>`;
  };
  A.studioAssetPreview=b=>{
    const asset=library.items.find(a=>a.id===Number(b.dataset.id));const root=app.querySelector(`[data-preview-for="${asset.id}"]`);
    root.innerHTML=`<div class="pwa-model-preview" data-asset-preview="${esc(asset.proxy_url)}"><p role="status">Loading model…</p></div>`;
  };
  if(!STUDIO_WORKSPACE_MODES.some(mode=>mode.key==='timeline'))STUDIO_WORKSPACE_MODES.splice(5,0,{key:'timeline',label:'Timeline',description:'Trim, arrange, animate positions and mix media.'});
  const previousStory=LightekStudioApp.story;
  LightekStudioApp.story=(record,mode)=>{
    if(!['timeline','audio'].includes(mode))return previousStory(record,mode);
    const assets=library.items.filter(a=>a.status==='ready'&&['audio','video','image'].includes(a.kind));
    const duration=Math.max(1,...timeline.clips.map(c=>c.start+c.out-c.in));
    return `<section class="studio-wave2"><span class="eb">${mode==='audio'?'Audio & mix':'Media timeline'}</span><h2>Shape the sequence.</h2><div class="pwa-post-actions"><select id="timeline-asset" aria-label="Asset">${assets.map(a=>`<option value="${a.id}">${esc(a.name)} · ${esc(a.kind)}</option>`).join('')}</select><button class="btn sm" data-a="studioTimelineAdd">Add clip</button><a class="btn sm" href="#/studio/library">Import media</a><button class="btn sm" data-a="studioTimelineSave">Save timeline</button><button class="btn sm" data-a="studioTimelinePreview">Play preview</button><button class="btn sm" data-a="studioTimelineStop">Stop preview</button><button class="btn p sm" data-a="studioTimelineQuote">Export quote</button></div><div class="pwa-post-actions"><label>Output <select data-timeline-setting="output"><option value="video" ${timeline.output==='video'?'selected':''}>MP4 video + mixed audio</option><option value="audio" ${timeline.output==='audio'?'selected':''}>WAV audio mix</option></select></label>${field('Width',timeline.width,'data-timeline-setting="width"')}${field('Height',timeline.height,'data-timeline-setting="height"')}</div><canvas class="pwa-timeline-preview" width="${Number(timeline.width)}" height="${Number(timeline.height)}" data-timeline-preview></canvas><p role="status" data-timeline-status></p><div class="pwa-timeline">${[...new Set(timeline.clips.map(c=>c.track))].sort((a,b)=>a-b).map(track=>`<div class="pwa-timeline-track"><small>Track ${track+1}</small>${timeline.clips.map((clip,i)=>clip.track===track?`<div class="pwa-timeline-bar" style="left:${clip.start/duration*100}%;width:${Math.max(1,(clip.out-clip.in)/duration*100)}%">${esc(library.items.find(a=>a.id===clip.asset_id)?.name||'Clip')} · ${i+1}</div>`:'').join('')}</div>`).join('')}</div>${timeline.clips.map((clip,i)=>`<details class="pwa-post" open><summary>Clip ${i+1} · ${esc(library.items.find(a=>a.id===clip.asset_id)?.name||'Media')}</summary><div class="pwa-editor-fields">${[['in','Source in · seconds'],['out','Source out · seconds'],['start','Timeline start · seconds'],['track','Track · starts at 0'],['gain','Volume · 1 = original'],['x','Horizontal position'],['y','Vertical position']].map(([key,label])=>field(label,clip[key]??0,`data-clip="${i}" data-clip-field="${key}"`)).join('')}<label><input type="checkbox" data-clip="${i}" data-clip-field="muted" ${clip.muted?'checked':''}> Mute audio</label></div><h4>Position and volume keyframes</h4>${(clip.keyframes||[]).map((frame,j)=>`<div class="pwa-editor-fields">${[['time','Time · seconds from clip start'],['x','X'],['y','Y'],['gain','Volume']].map(([key,label])=>field(label,frame[key],`data-clip="${i}" data-keyframe="${j}" data-frame-field="${key}"`)).join('')}<button class="btn sm" data-a="studioTimelineFrameRemove" data-index="${i}" data-frame="${j}">Remove keyframe</button></div>`).join('')}<div class="pwa-post-actions"><button class="btn sm" data-a="studioTimelineFrame" data-index="${i}">Add keyframe</button><button class="btn sm" data-a="studioTimelineRemove" data-index="${i}">Remove clip</button></div></details>`).join('')}</section>`;
  };
  A.studioTimelineAdd=()=>{const asset=library.items.find(a=>a.id===Number(document.getElementById('timeline-asset').value));if(!asset)return;timeline.clips.push({asset_id:asset.id,kind:asset.kind,in:0,out:asset.kind==='image'?5:Math.min(asset.metadata.duration||5,5),start:0,track:timeline.clips.length,gain:1,x:0,y:0,muted:false,keyframes:[]});render(1);};
  A.studioTimelineRemove=b=>{timeline.clips.splice(Number(b.dataset.index),1);render(1);};
  A.studioTimelineFrame=b=>{const clip=timeline.clips[Number(b.dataset.index)];clip.keyframes||=[];clip.keyframes.push({time:clip.keyframes.length?Math.min(clip.out-clip.in,clip.keyframes.at(-1).time+1):0,x:clip.x||0,y:clip.y||0,gain:clip.gain});render(1);};
  A.studioTimelineFrameRemove=b=>{timeline.clips[Number(b.dataset.index)].keyframes.splice(Number(b.dataset.frame),1);render(1);};
  async function saveTimeline(){const record=current();const result=await call('timeline.save',{scene_id:record.scene.id,lock_version:record.scene.lock_version,timeline});record.scene.lock_version=result.lock_version;record.scene.settings.timeline=result.timeline;timeline=result.timeline;return result;}
  A.studioTimelineSave=()=>run(async()=>{await saveTimeline();toast('Timeline saved');});
  A.studioTimelineQuote=()=>run(async()=>{await saveTimeline();const result=await call('timeline.quote',{scene_id:current().scene.id});LightekStudioApp.setQuote(result);ST.workspaceMode='publish';render(1);});
  app.addEventListener('change',e=>{
    const el=e.target;if(el.dataset.timelineSetting){timeline[el.dataset.timelineSetting]=el.dataset.timelineSetting==='output'?el.value:Number(el.value);render(1);}
    if(el.dataset.clipField){timeline.clips[Number(el.dataset.clip)][el.dataset.clipField]=el.type==='checkbox'?el.checked:Number(el.value);render(1);}
    if(el.dataset.frameField){timeline.clips[Number(el.dataset.clip)].keyframes[Number(el.dataset.keyframe)][el.dataset.frameField]=Number(el.value);}
  });
  app.addEventListener('submit',e=>{
    const form=e.target.closest('[data-media-form]');if(!form)return;e.preventDefault();run(async()=>{
      if(form.dataset.mediaForm==='import'){
        const file=form.elements.file.files[0];if(!file||file.size>250*1024*1024)throw Error('Choose a file smaller than 250 MB.');
        const notice=form.querySelector('[data-import-status]');notice.textContent='Uploading…';const body=new FormData();body.append('file',file);body.append('purpose','studio_asset');
        const response=await fetch('/api/lightek/pwa/uploads',{method:'POST',credentials:'same-origin',headers:nevaeh.csrfHeaders(),body});const upload=await nevaeh.parseResponse(response);
        await call('asset.import',{signed_id:upload.signed_id,name:form.elements.name.value.trim()||file.name,request_key:form.dataset.requestKey||=crypto.randomUUID()});
        await loadAssets(true);toast('Import queued');
      }else if(form.dataset.mediaForm==='place'){
        const result=await call('asset.place',{asset_id:Number(form.dataset.id),scene_id:Number(form.elements.scene_id.value),category:form.elements.category.value});await A.studioLoad(true);location.hash='#/studio/'+result.scene_id;
      }
    });
  });
  function stopPreview(){if(!preview)return;cancelAnimationFrame(preview.frame);preview.items.forEach(item=>{if(item.el.pause)item.el.pause();item.el.src='';});preview.audio.close();preview=null;}
  const interpolate=(frames,key,t,base)=>{if(!frames?.length)return base;const ordered=[...frames].sort((a,b)=>a.time-b.time);if(t<=ordered[0].time)return ordered[0][key];for(let i=1;i<ordered.length;i++)if(t<ordered[i].time){const a=ordered[i-1],b=ordered[i],ratio=(t-a.time)/(b.time-a.time);return a[key]+(b[key]-a[key])*ratio;}return ordered.at(-1)[key];};
  A.studioTimelineStop=stopPreview;
  A.studioTimelinePreview=()=>run(async()=>{
    stopPreview();const canvas=app.querySelector('[data-timeline-preview]');if(!canvas)return;const audio=new AudioContext();await audio.resume();const items=[];
    for(const clip of timeline.clips){const asset=library.items.find(a=>a.id===clip.asset_id);if(!asset)throw Error('Reload the media library first.');const el=document.createElement(asset.kind==='image'?'img':asset.kind==='audio'?'audio':'video');el.src=asset.proxy_url;el.preload='auto';el.playsInline=true;let gain=null;if(asset.kind!=='image'){gain=audio.createGain();audio.createMediaElementSource(el).connect(gain);gain.connect(audio.destination);}items.push({clip,asset,el,gain,playing:false});}
    preview={audio,items,frame:0};const state=preview,start=performance.now(),ctx=canvas.getContext('2d');
    function draw(){if(preview!==state)return;if(!canvas.isConnected){stopPreview();return;}const t=(performance.now()-start)/1000;ctx.fillStyle='black';ctx.fillRect(0,0,canvas.width,canvas.height);let duration=0;
      for(const item of items){const {clip,el,asset,gain}=item,end=clip.start+clip.out-clip.in;duration=Math.max(duration,end);if(t<clip.start||t>=end){if(item.playing){el.pause?.();item.playing=false;}continue;}
        if(asset.kind!=='image'&&!item.playing){el.currentTime=clip.in+(t-clip.start);el.play().catch(error=>{const notice=app.querySelector('[data-timeline-status]');if(notice)notice.textContent=error.message;});item.playing=true;}
        if(gain)gain.gain.setValueAtTime(clip.muted?0:interpolate(clip.keyframes,'gain',t-clip.start,clip.gain),audio.currentTime);
        const w=el.videoWidth||el.naturalWidth,h=el.videoHeight||el.naturalHeight;if(w&&h){const scale=Math.min(canvas.width/w,canvas.height/h);ctx.drawImage(el,interpolate(clip.keyframes,'x',t-clip.start,clip.x||0),interpolate(clip.keyframes,'y',t-clip.start,clip.y||0),w*scale,h*scale);}
      }
      const notice=app.querySelector('[data-timeline-status]');if(notice)notice.textContent=t.toFixed(1)+' seconds';if(t>=duration){stopPreview();return;}state.frame=requestAnimationFrame(draw);
    }draw();
  });
  new MutationObserver(()=>{if(preview&&!app.querySelector('[data-timeline-preview]'))stopPreview();}).observe(app,{childList:true,subtree:true});
})();
