/* Media, editing and color surfaces over the same persisted timeline and preview engine. */
(() => {
  const state={source:null,filter:'all',query:'',tab:'transform',zoom:1,ranges:new Map(),uploads:[],drag:null};
  const t=()=>LightekStudioTimeline.get(),editor=()=>LightekStudioTimeline.editor();
  const esc=value=>E(String(value??''));
  const icon={video:'▣',audio:'♫',image:'▧'};
  const length=c=>(c.out-c.in)/(c.speed||1);
  const duration=()=>Math.max(10,...t().clips.map(c=>c.start+length(c)));
  const clock=time=>{const fps=t()?.fps||24,n=Math.max(0,Number(time)||0);return `${String(Math.floor(n/3600)).padStart(2,'0')}:${String(Math.floor(n/60)%60).padStart(2,'0')}:${String(Math.floor(n)%60).padStart(2,'0')}:${String(Math.floor(n%1*fps)).padStart(2,'0')}`;};
  const button=(action,label,extra='')=>`<button type="button" class="ew-button" data-ew="${action}" ${extra}>${label}</button>`;
  const numeric=(index,key,label,fallback=0,min,max,step=.01)=>`<label class="ew-field"><span>${label}</span><input aria-label="${label}" type="number" data-clip="${index}" data-clip-field="${key}" value="${t().clips[index][key]??fallback}" step="${step}" ${min!==undefined?`min="${min}"`:''} ${max!==undefined?`max="${max}"`:''}></label>`;
  const sourceLimit=asset=>Math.min(Number(asset?.metadata?.duration)||5,600);
  const sourceSelection=asset=>state.ranges.get(asset?.id)||{in:0,out:sourceLimit(asset)};
  function sourceRange(asset){
    const range=sourceSelection(asset);
    return `<div class="ew-source-range"><div>${button('mark-in','Mark in')}${button('mark-out','Mark out')}</div><label>In (seconds)<input aria-label="Source range in" data-ew-range="in" type="number" min="0" max="${sourceLimit(asset)}" step="0.01" value="${range.in}"></label><label>Out (seconds)<input aria-label="Source range out" data-ew-range="out" type="number" min="0" max="${sourceLimit(asset)}" step="0.01" value="${range.out}"></label><small>Choose a range, then append it or drag the media onto a track.</small></div>`;
  }
  function uploadQueue(){
    return `<section class="ew-import-queue" aria-label="Import progress" aria-live="polite">${state.uploads.map((u,i)=>`<div class="ew-import-item" data-upload-row="${i}"><strong>${esc(u.file.name)}</strong><span>${esc(u.error||({queued:'Waiting to upload',uploading:`Uploading ${u.progress||0}%`,registering:'Upload complete · adding to media pool',imported:editor().assets.find(a=>a.id===u.assetId)?.status==='ready'?'Ready · append or drag onto the timeline':editor().assets.find(a=>a.id===u.assetId)?.status==='failed'?'Preparation failed · select the media for details':'Added to media pool · preparing preview'}[u.status]))}</span>${u.status==='uploading'?`<progress max="100" value="${u.progress||0}"></progress>`:''}${u.status==='failed'?button('retry-upload','Retry import',`data-upload="${i}"`):''}</div>`).join('')}</section>`;
  }
  function refreshQueue(){const el=app.querySelector('.ew-import-queue');if(el)el.outerHTML=uploadQueue();}
  function upload(file,progress){
    return new Promise((resolve,reject)=>{
      const xhr=new XMLHttpRequest(),body=new FormData();body.append('file',file);body.append('purpose','studio_asset');
      xhr.open('POST',LightekStudioUploadUrl);xhr.withCredentials=true;xhr.timeout=300000;
      Object.entries(nevaeh.csrfHeaders()).forEach(([key,value])=>xhr.setRequestHeader(key,value));xhr.setRequestHeader('Accept','application/json');
      xhr.upload.onprogress=e=>{if(e.lengthComputable)progress(Math.round(e.loaded/e.total*100));};
      xhr.onload=()=>{let data={};try{data=JSON.parse(xhr.responseText);}catch{}if(xhr.status>=200&&xhr.status<300&&data.signed_id)resolve(data);else reject(Error(data.error||`Upload failed (${xhr.status}). Retry this file.`));};
      xhr.onerror=()=>reject(Error('Connection lost. Check your connection and retry this file.'));
      xhr.ontimeout=()=>reject(Error('Upload timed out. Retry this file.'));
      xhr.send(body);
    });
  }
  async function importFile(item){
    if(['uploading','registering'].includes(item.status))return;
    item.error='';
    try{
      if(item.file.size>250*1024*1024)throw Error('Choose a file smaller than 250 MB.');
      if(!item.signedId){item.status='uploading';refreshQueue();const result=await upload(item.file,p=>{item.progress=p;refreshQueue();});item.signedId=result.signed_id;}
      item.status='registering';refreshQueue();
      const result=await nevaeh.execute({capability:'studio.workspace.asset.import',payload:{signed_id:item.signedId,name:item.file.name,request_key:item.key}});
      item.status='imported';item.assetId=result.result.asset_id;state.source=item.assetId;
      await A.studioAssetsReload();
    }catch(error){item.status='failed';item.error=error.message;}
    finally{refreshQueue();}
  }
  async function queueFiles(files){
    const items=files.map(file=>({file,key:crypto.randomUUID(),status:'queued',progress:0}));state.uploads.push(...items);render();
    for(const item of items)await importFile(item);
  }
  function renderInto(container,html){
    const old=container.querySelector('.edit-workbench'),template=document.createElement('template');template.innerHTML=html;
    const next=template.content.querySelector('.edit-workbench');
    if(!old||!next||old.dataset.editorScene!==next.dataset.editorScene)return false;
    old.dataset.editorMode=next.dataset.editorMode;
    for(const selector of ['.ew-bin','.ew-timeline'])old.querySelector(selector).replaceWith(next.querySelector(selector));
    const inspector=old.querySelector('.ew-inspector'),newInspector=next.querySelector('.ew-inspector');
    const editing=inspector.contains(document.activeElement)&&document.activeElement.matches('input,textarea,select');
    if(editing&&inspector.dataset.selected===newInspector.dataset.selected&&inspector.dataset.tab===newInspector.dataset.tab){
      inspector.querySelectorAll('output').forEach((el,i)=>{el.textContent=newInspector.querySelectorAll('output')[i]?.textContent||'';});
    }else inspector.replaceWith(newInspector);
    const source=old.querySelector('.ew-source'),newSource=next.querySelector('.ew-source');
    const media=source.querySelector('video,audio,img'),newMedia=newSource.querySelector('video,audio,img');
    if(media&&newMedia&&media.getAttribute('src')===newMedia.getAttribute('src')){
      // Keep the media node connected: detaching a video resets its seek and playback state.
      source.querySelectorAll(':scope > :not(.ew-source-image)').forEach(el=>el.remove());
      source.prepend(newSource.querySelector('.ew-pane-title'));
      Array.from(newSource.children).filter(el=>!el.matches('.ew-source-image')).forEach(el=>source.append(el));
    }else source.replaceWith(newSource);
    const program=old.querySelector('.ew-program'),newProgram=next.querySelector('.ew-program');
    for(const selector of ['.ew-pane-title','.ew-program-transport','.ew-preview-status'])program.querySelector(selector).replaceWith(newProgram.querySelector(selector));
    const canvas=program.querySelector('canvas'),newCanvas=newProgram.querySelector('canvas');
    if(canvas.width!==newCanvas.width||canvas.height!==newCanvas.height){canvas.width=newCanvas.width;canvas.height=newCanvas.height;}
    program.querySelectorAll('.ew-viewer-caption,.ew-viewer-empty').forEach(el=>el.remove());
    newProgram.querySelectorAll('.ew-viewer-caption,.ew-viewer-empty').forEach(el=>program.querySelector('.ew-program-image').append(el));
    return true;
  }
  let retained=null,mountId=0;
  function beforeRender(){
    const work=app.querySelector('.edit-workbench');
    if(!work){retained=null;return;}
    retained={scene:Number(work.dataset.editorScene),source:state.source,sourceImage:work.querySelector('.ew-source-image'),canvas:work.querySelector('[data-timeline-preview]'),timeline:JSON.stringify(t()),
      scrolls:['.ew-track-scroll','.ew-inspector-scroll','.ew-bin-scroll'].map(selector=>({selector,left:work.querySelector(selector)?.scrollLeft||0,top:work.querySelector(selector)?.scrollTop||0}))};
  }
  function mount(){
    const work=app.querySelector('.edit-workbench');if(!work){retained=null;return;}
    const same=retained?.scene===studioCurrentSceneId();
    if(same){
      const source=work.querySelector('.ew-source-image');
      // Retain the decoded source, including the user's source playhead, through inspector/pool updates.
      if(source!==retained.sourceImage&&retained.source===state.source&&retained.sourceImage?.querySelector('video,audio,img')&&source?.querySelector('video,audio,img')?.getAttribute('src')===retained.sourceImage.querySelector('video,audio,img').getAttribute('src'))source.replaceWith(retained.sourceImage);
      if(work.querySelector('[data-timeline-preview]')!==retained.canvas&&retained.timeline===JSON.stringify(t())&&retained.canvas)work.querySelector('[data-timeline-preview]').replaceWith(retained.canvas);
      retained.scrolls.forEach(({selector,left,top})=>{const el=work.querySelector(selector);if(el){el.scrollLeft=left;el.scrollTop=top;}});
    }
    retained=null;const id=++mountId;
    queueMicrotask(()=>{if(id===mountId&&work.isConnected)run(previewFrame);});
  }
  function mediaBin(){const e=editor(),items=e.assets.filter(a=>['audio','video','image'].includes(a.kind)).filter(a=>(state.filter==='all'||a.kind===state.filter)&&(a.name||'Untitled').toLowerCase().includes(state.query.toLowerCase()));return `<aside class="ew-bin"><div class="ew-pane-title"><strong>Media pool</strong><span>${items.length} items</span></div><label class="ew-search"><span class="sr-only">Find media</span><input aria-label="Find media" data-ew-search placeholder="Search your media" value="${esc(state.query)}"></label><nav class="ew-bin-filters" aria-label="Media filters">${[['all','All'],['video','Video'],['audio','Audio'],['image','Stills']].map(([key,label])=>button('filter',label,`data-filter="${key}" aria-pressed="${state.filter===key}"`)).join('')}</nav><div class="ew-bin-scroll">${items.map(a=>`<button type="button" class="ew-asset ${Number(a.id)===Number(state.source)?'selected':''}" data-ew="source" data-id="${a.id}" draggable="${a.status==='ready'}" aria-label="Preview ${esc(a.name)}"><div class="ew-thumb">${a.thumbnail_url?`<img src="${esc(a.thumbnail_url)}" alt="">`:`<span>${icon[a.kind]}</span>`}<small>${a.kind==='image'?'STILL':a.metadata?.duration?clock(a.metadata.duration):a.status}</small></div><strong>${esc(a.name)}</strong><span>${esc(a.kind)} · ${a.status==='ready'?'Ready':a.status==='failed'?'Needs attention':'Preparing…'}</span></button>`).join('')||`<div class="ew-empty-bin"><span>＋</span><h3>${e.loading?'Opening media…':'Start with your footage'}</h3><p>${state.query?'No media matches your search.':'Import video, audio or stills. Your original files stay in the production library.'}</p></div>`}</div>${e.error?`<p class="ew-error" role="alert">${esc(e.error)}</p>`:''}${uploadQueue()}${button('refresh','Refresh media')}${e.nextBefore?button('more','Load more media'):''}${button('insert','Append selected clip',e.assets.some(a=>a.id===state.source&&a.status==='ready')?'':'disabled')}<label class="ew-import">＋ Import media<input type="file" data-ew-upload multiple accept="video/*,audio/*,image/*" hidden></label><small class="ew-import-hint">Or drop files here · up to 250 MB each</small><a class="ew-library-link" href="#/studio/${studioCurrentSceneId()}/assets">Full asset library</a></aside>`;}
  function sourceViewer(){const source=editor().assets.find(a=>Number(a.id)===Number(state.source)),url=source?.proxy_url;return `<section class="ew-source"><div class="ew-pane-title"><strong>Source</strong><span>${esc(source?.name||'Choose a clip')}</span></div><div class="ew-source-image">${url?(source.kind==='image'?`<img src="${esc(url)}" alt="${esc(source.name)}">`:`<${source.kind==='audio'?'audio':'video'} src="${esc(url)}" controls playsinline preload="metadata"></${source.kind==='audio'?'audio':'video'}>`):`<div class="ew-viewer-empty"><span>${source?icon[source.kind]:'▣'}</span><p>${source?source.status==='failed'?esc(source.error||'Preparation failed. Retry below.'):source.status==='ready'?'No prepared preview is available.':'Preparing your preview. You can keep editing while this finishes.':'Select media to review it here.'}</p></div>`}</div>${source?.status==='failed'?button('retry-asset','Retry preparation',`data-id="${source.id}"`):''}${source?.status==='ready'?sourceRange(source):''}<div class="ew-source-footer"><span>${source?esc(source.kind.toUpperCase()):'SOURCE VIEWER'}</span>${button('insert','Append to timeline',!source||source.status!=='ready'?'disabled':'')}</div></section>`;}
  function programViewer(record){const timeline=t(),clip=timeline.clips[editor().selected],a=editor().assets.find(a=>a.id===clip?.asset_id);return `<section class="ew-program"><div class="ew-pane-title"><strong>Program</strong><span>${esc(record.scene.name)} · ${timeline.width} × ${timeline.height}</span></div><div class="ew-program-image"><canvas width="960" height="${Math.round(960*timeline.height/timeline.width)}" data-timeline-preview aria-label="Program viewer"></canvas>${!timeline.clips.length?'<div class="ew-viewer-empty"><span>▷</span><strong>Your story starts here.</strong><p>Import media, then drag a clip onto the timeline.</p></div>':`<span class="ew-viewer-caption">${esc(a?.name||'Episode sequence')} · press Play to review</span>`}</div><div class="ew-program-transport">${button('start','|◁','aria-label="Jump to beginning"')}${button('play',LightekStudioTimeline.playing()?'❚❚':'▶','aria-label="Play or pause"')}${button('stop','■','aria-label="Stop playback"')}<output data-edit-time>${clock(editor().playhead)}</output><span>${timeline.fps||24} fps</span>${button('fit','Fit','aria-label="Fit timeline"')}</div><div class="ew-preview-status" role="status" data-timeline-status>Ready · preview uses prepared media</div></section>`;}
  function inspector(mode){const e=editor(),clip=t().clips[e.selected],a=e.assets.find(a=>a.id===clip?.asset_id);const tab=mode==='color'?'color':state.tab;const titles=t().titles||[];return `<aside class="ew-inspector" data-selected="${e.selected}" data-tab="${tab}"><div class="ew-pane-title"><strong>${mode==='color'?'Color & finish':'Inspector'}</strong><span>${clip?'Clip '+(e.selected+1):'No selection'}</span></div><nav class="ew-inspector-tabs" aria-label="Inspector sections">${[['transform','Picture'],['color','Color'],['audio','Audio'],['titles','Titles']].map(([key,label])=>button('inspector',label,`data-tab="${key}" aria-pressed="${tab===key}"`)).join('')}</nav><div class="ew-inspector-scroll"><h3>${esc(a?.name||'Select a timeline clip')}</h3>${tab==='titles'?`${button('title','＋ Add title at playhead')}${titles.map((title,i)=>`<section class="ew-inspector-group"><label class="ew-field"><span>Title text</span><textarea data-title="${i}" data-title-field="text">${esc(title.text)}</textarea></label>${[['start','Start'],['end','End'],['x','X'],['y','Y'],['size','Font size']].map(([key,label])=>`<label class="ew-field"><span>${label}</span><input type="number" value="${title[key]}" data-title="${i}" data-title-field="${key}"></label>`).join('')}<button class="ew-button" data-a="studioTimelineTitleRemove" data-index="${i}">Remove title</button></section>`).join('')}`:!clip?'<p class="ew-muted">Select a clip to change its properties. Every change stays with this sequence.</p>':tab==='transform'?`<section class="ew-inspector-group"><h4>Timing</h4>${numeric(e.selected,'start','Timeline start',0,0)}${numeric(e.selected,'in','Source in',0,0)}${numeric(e.selected,'out','Source out',5,0)}${numeric(e.selected,'speed','Speed',1,.25,4)}</section><section class="ew-inspector-group"><h4>Transform</h4>${numeric(e.selected,'x','Position X')}${numeric(e.selected,'y','Position Y')}${numeric(e.selected,'scale','Scale',1,.1,4)}${numeric(e.selected,'opacity','Opacity',1,0,1)}</section>`:tab==='color'?`<section class="ew-inspector-group"><h4>Primary adjustments</h4>${[['brightness','Brightness',0,-1,1],['contrast','Contrast',1,0,2],['saturation','Saturation',1,0,3]].map(([key,label,fallback,min,max])=>`<label class="ew-color-control"><span>${label}<output>${Number(clip[key]??fallback).toFixed(2)}</output></span><input aria-label="${label}" type="range" min="${min}" max="${max}" step="0.01" value="${clip[key]??fallback}" data-clip="${e.selected}" data-clip-field="${key}"></label>`).join('')}${button('reset-color','Reset color')}<p class="ew-muted">Preview the selected shot to see changes. Export applies the final processing.</p></section>`:`<section class="ew-inspector-group"><h4>Clip audio</h4>${numeric(e.selected,'gain','Clip gain',1,0,4)}${numeric(e.selected,'fade_in','Fade in',0,0)}${numeric(e.selected,'fade_out','Fade out',0,0)}${numeric(e.selected,'highpass','Low cut (Hz)',0,0)}<h4>Track mix</h4>${[['gain','Track gain',1,0,4],['pan','Track pan',0,-1,1]].map(([key,label,fallback,min,max])=>`<label class="ew-field"><span>${label}</span><input type="number" aria-label="${label}" value="${t().tracks?.find(track=>track.id===clip.track)?.[key]??fallback}" min="${min}" max="${max}" step="0.05" data-track="${clip.track}" data-track-field="${key}"></label>`).join('')}<label class="ew-check"><input type="checkbox" data-clip="${e.selected}" data-clip-field="muted" ${clip.muted?'checked':''}> Mute clip</label><label class="ew-check"><input type="checkbox" data-clip="${e.selected}" data-clip-field="denoise" ${clip.denoise?'checked':''}> Reduce noise on export</label></section>`}${clip?`<details class="ew-inspector-group"><summary>Keyframes</summary><button class="ew-button" data-a="studioTimelineFrame" data-index="${e.selected}">Set position & gain at playhead</button>${(clip.keyframes||[]).map((f,j)=>`<div class="ew-keyframe"><strong>${clock(f.time)}</strong>${['time','x','y','gain'].map(key=>`<label class="ew-field"><span>${key}</span><input type="number" value="${f[key]}" data-clip="${e.selected}" data-keyframe="${j}" data-frame-field="${key}"></label>`).join('')}<button class="ew-button" data-a="studioTimelineFrameRemove" data-index="${e.selected}" data-frame="${j}">Remove keyframe</button></div>`).join('')}</details>`:''}</div></aside>`;}
  function timeline(){const timeline=t(),e=editor(),span=duration(),tracks=[...new Set([0,1,...timeline.clips.map(c=>c.track),...(timeline.tracks||[]).map(a=>a.id)])].sort((a,b)=>a-b);return `<section class="ew-timeline"><header class="ew-edit-toolbar"><div><strong>Timeline 01</strong><span>${timeline.clips.length} clips · ${clock(span)}</span></div><div>${button('split','Split','title="Split selected clip at playhead" '+(t().clips[e.selected]&&e.playhead>t().clips[e.selected].start&&e.playhead<t().clips[e.selected].start+length(t().clips[e.selected])?'':'disabled'))}${button('duplicate','Duplicate',t().clips[e.selected]?'':'disabled')}${button('remove','Delete',t().clips[e.selected]?'':'disabled')}${button('undo','↶','aria-label="Undo" '+(e.undo?'':'disabled'))}${button('redo','↷','aria-label="Redo" '+(e.redo?'':'disabled'))}</div><label>Zoom<input aria-label="Timeline zoom" type="range" min="1" max="5" step=".5" value="${state.zoom}" data-ew-zoom></label></header><div class="ew-track-scroll"><div class="ew-track-canvas" style="--ew-track-width:${state.zoom*100}%"><div class="ew-ruler"><span>TRACKS</span><div data-ew-ruler aria-label="Seek in timeline">${Array.from({length:11},(_,i)=>`<button data-ew="seek" data-time="${span*i/10}" style="left:${i*10}%">${clock(span*i/10)}</button>`).join('')}</div></div>${tracks.map(id=>{const audio=timeline.clips.filter(c=>c.track===id).every(c=>e.assets.find(a=>a.id===c.asset_id)?.kind==='audio')&&id!==0;const mix=timeline.tracks?.find(m=>m.id===id)||{};return `<div class="ew-track"><div class="ew-track-head"><strong>${esc(mix.name||`${audio?'A':'V'}${id+1}`)}</strong><span>${audio?'Audio':'Picture / media'}</span><div><label title="Mute"><input type="checkbox" data-track="${id}" data-track-field="muted" ${mix.muted?'checked':''}>M</label><label title="Solo"><input type="checkbox" data-track="${id}" data-track-field="solo" ${mix.solo?'checked':''}>S</label></div></div><div class="ew-lane" data-ew-lane data-track-id="${id}">${timeline.clips.map((c,i)=>{if(c.track!==id)return '';const a=e.assets.find(a=>a.id===c.asset_id);return `<button draggable="true" data-ew="clip" data-index="${i}" class="ew-clip ${a?.kind==='audio'?'audio':''} ${e.selected===i?'selected':''}" style="left:${c.start/span*100}%;width:${Math.max(.25,length(c)/span*100)}%" aria-pressed="${e.selected===i}" aria-label="Select ${esc(a?.name||'clip')}"><i class="ew-trim ew-trim-in" data-ew-trim="in" title="Drag to trim start"></i><i class="ew-trim ew-trim-out" data-ew-trim="out" title="Drag to trim end"></i><span>${icon[a?.kind]||'▣'} ${esc(a?.name||'Media')}</span><small>${clock(length(c))}</small></button>`;}).join('')}<i class="ew-playhead" style="left:${e.playhead/span*100}%"></i></div></div>`;}).join('')}<div class="ew-track ew-empty-track"><span>Drop media onto V1 for picture or A2 for sound · drag clip edges to trim</span></div></div></div><footer class="ew-timeline-footer"><span>Drag to arrange · Space to play · Delete to remove · Ctrl/Cmd Z to undo</span><label>Playhead<input type="range" data-ew-scrub aria-label="Timeline playhead" min="0" max="${span}" value="${e.playhead}" step="${1/(timeline.fps||24)}"></label></footer></section>`;}
  function view(record,mode){return `<section class="edit-workbench" aria-label="Media Studio editor" data-editor-mode="${mode}" data-editor-scene="${record.scene.id}"><div class="ew-work-area">${mediaBin()}<div class="ew-viewers">${sourceViewer()}${programViewer(record)}</div>${inspector(mode)}</div>${timeline()}</section>`;}
  function run(fn){Promise.resolve().then(fn).catch(error=>toast(error.message));}
  async function previewFrame(){const e=editor();if(!app.querySelector('.edit-workbench')||e.loading||LightekStudioTimeline.playing())return;if(!t().clips.length){const canvas=app.querySelector('[data-timeline-preview]'),ctx=canvas.getContext('2d');ctx.fillStyle='black';ctx.fillRect(0,0,canvas.width,canvas.height);return;}const active=t().clips.filter(c=>e.playhead>=c.start&&e.playhead<c.start+length(c));if(active.some(c=>!e.assets.find(a=>a.id===c.asset_id)?.proxy_url))return;await A.studioTimelinePreview(true);}
  function seek(seconds){LightekStudioTimeline.playhead(seconds);render();}
  app.addEventListener('click',event=>{const b=event.target.closest('[data-ew]');if(!b)return;const action=b.dataset.ew;run(async()=>{
    if(action==='source'){state.source=Number(b.dataset.id);render();}
    if(action==='refresh')await A.studioAssetsReload();
    if(action==='more')await A.studioAssetsMore();
    if(action==='retry-upload')await importFile(state.uploads[Number(b.dataset.upload)]);
    if(action==='retry-asset'){await nevaeh.execute({capability:'studio.workspace.asset.retry',payload:{asset_id:Number(b.dataset.id)}});await A.studioAssetsReload();}
    if(action==='mark-in'||action==='mark-out'){const media=app.querySelector('.ew-source video,.ew-source audio'),asset=editor().assets.find(a=>a.id===state.source);if(media&&asset){const range={...sourceSelection(asset),[action==='mark-in'?'in':'out']:Math.min(sourceLimit(asset),media.currentTime)};if(range.out<=range.in){toast('The out point must follow the in point.');return;}state.ranges.set(asset.id,range);render();}}
    if(action==='filter'){state.filter=b.dataset.filter;render();}
    if(action==='inspector'){state.tab=b.dataset.tab;if(LightekStudioProduction.mode()==='color')LightekStudioProduction.go('edit');else render();}
    if(action==='insert'){const asset=editor().assets.find(a=>a.id===state.source);LightekStudioTimeline.insert(state.source,undefined,undefined,sourceSelection(asset));toast('Clip appended. Drag its edges to trim; drag the clip to move it.');}
    if(action==='clip')A.studioTimelineSelect(b);
    if(action==='split')A.studioTimelineSplit();
    if(action==='duplicate')A.studioTimelineDuplicate();
    if(action==='remove')A.studioTimelineRemove({dataset:{index:editor().selected}});
    if(action==='undo')A.studioTimelineUndo();if(action==='redo')A.studioTimelineRedo();
    if(action==='title')A.studioTimelineTitleAdd();
    if(action==='start')seek(0);if(action==='seek')seek(Number(b.dataset.time));
    if(action==='play'){if(LightekStudioTimeline.playing())A.studioTimelineStop();else await A.studioTimelinePreview();}
    if(action==='stop')A.studioTimelineStop();
    if(action==='play'){const play=app.querySelector('[data-ew=play]');if(play)play.textContent=LightekStudioTimeline.playing()?'❚❚':'▶';}
    if(action==='fit'){state.zoom=1;render();}

    if(action==='reset-color'){const selected=editor().selected;for(const [key,value] of [['brightness',0],['contrast',1],['saturation',1]]){const input=app.querySelector(`[data-clip="${selected}"][data-clip-field="${key}"]`);if(input){input.value=value;input.dispatchEvent(new Event('change',{bubbles:true}));}}}
  });});
  app.addEventListener('input',event=>{if(event.target.matches('[data-ew-search]')){state.query=event.target.value;const position=event.target.selectionStart;render();const input=app.querySelector('[data-ew-search]');input.focus();input.setSelectionRange(position,position);}});
  app.addEventListener('change',event=>{if(event.target.matches('[data-ew-zoom]')){state.zoom=Number(event.target.value);render();}if(event.target.matches('[data-ew-scrub]'))seek(event.target.value);if(event.target.matches('[data-ew-upload]')){const files=Array.from(event.target.files);event.target.value='';queueFiles(files);}});
  app.addEventListener('dragstart',event=>{const asset=event.target.closest('.ew-asset'),clip=event.target.closest('.ew-clip');if(event.target.closest('[data-ew-trim]')){event.preventDefault();return;}if(asset)event.dataTransfer.setData('application/x-lightek-media',asset.dataset.id);if(clip)event.dataTransfer.setData('application/x-lightek-edit-clip',clip.dataset.index);});
  app.addEventListener('dragover',event=>{if(event.target.closest('[data-ew-lane],.ew-bin')||event.dataTransfer.types.includes('Files')){event.preventDefault();event.dataTransfer.dropEffect='copy';}});
  app.addEventListener('drop',event=>{if(event.dataTransfer.files.length){event.preventDefault();queueFiles(Array.from(event.dataTransfer.files));return;}const lane=event.target.closest('[data-ew-lane]');if(!lane)return;event.preventDefault();const box=lane.getBoundingClientRect(),start=Math.max(0,(event.clientX-box.left)/box.width*duration()),asset=event.dataTransfer.getData('application/x-lightek-media'),clip=event.dataTransfer.getData('application/x-lightek-edit-clip');run(()=>{if(asset)LightekStudioTimeline.insert(Number(asset),start,Number(lane.dataset.trackId),sourceSelection(editor().assets.find(a=>a.id===Number(asset))));else if(clip!=='')LightekStudioTimeline.move(Number(clip),start,Number(lane.dataset.trackId));});});
  app.addEventListener('keydown',event=>{if(!app.querySelector('.edit-workbench')||event.target.closest('input,select,textarea,[contenteditable=true]'))return;if(event.code==='Space'){event.preventDefault();app.querySelector('[data-ew=play]').click();}if(event.key==='Delete'||event.key==='Backspace'){event.preventDefault();app.querySelector('[data-ew=remove]').click();}if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='z'){event.preventDefault();app.querySelector(`[data-ew=${event.shiftKey?'redo':'undo'}]`).click();}});
  app.addEventListener('click',event=>{if(event.target.closest('[data-ew]'))return;const lane=event.target.closest('[data-ew-ruler],[data-ew-lane]');if(lane){const rect=lane.getBoundingClientRect();seek((event.clientX-rect.left)/rect.width*duration());}});
  app.addEventListener('change',event=>{const edge=event.target.dataset.ewRange;if(!edge)return;const asset=editor().assets.find(a=>a.id===state.source);if(!asset)return;const range={...sourceSelection(asset),[edge]:Number(event.target.value)};if(range.in<0||range.out<=range.in||range.out>sourceLimit(asset)){toast('Choose an out point after the in point within this source.');event.target.value=sourceSelection(asset)[edge];return;}state.ranges.set(asset.id,range);});
  app.addEventListener('pointerdown',event=>{
    const handle=event.target.closest('[data-ew-trim]');if(!handle)return;event.preventDefault();event.stopPropagation();
    const clip=handle.closest('.ew-clip'),lane=clip.closest('[data-ew-lane]');handle.setPointerCapture(event.pointerId);
    state.drag={handle,index:Number(clip.dataset.index),edge:handle.dataset.ewTrim,x:event.clientX,pixels:lane.getBoundingClientRect().width/spanDuration(),clip,left:clip.style.left,width:clip.style.width};
  });
  const spanDuration=()=>duration();
  app.addEventListener('pointermove',event=>{
    const d=state.drag;if(!d)return;const delta=(event.clientX-d.x)/d.pixels,c=t().clips[d.index],fps=t().fps||24;
    const min=d.edge==='in'?Math.max(-c.in/(c.speed||1),-c.start):-length(c)+1/fps;
    const max=d.edge==='in'?length(c)-1/fps:Math.min(600-c.start-length(c),((editor().assets.find(a=>a.id===c.asset_id)?.kind==='image'?600:sourceLimit(editor().assets.find(a=>a.id===c.asset_id)))-c.out)/(c.speed||1));
    const bounded=Math.max(min,Math.min(max,delta));
    d.clip.style.left=(c.start+(d.edge==='in'?bounded:0))/duration()*100+'%';d.clip.style.width=(length(c)+(d.edge==='in'?-bounded:bounded))/duration()*100+'%';
  });
  app.addEventListener('pointerup',event=>{const d=state.drag;if(!d)return;state.drag=null;d.handle.releasePointerCapture(event.pointerId);run(()=>LightekStudioTimeline.trim(d.index,d.edge,(event.clientX-d.x)/d.pixels));});
  app.addEventListener('pointercancel',()=>{const d=state.drag;if(d){d.clip.style.left=d.left;d.clip.style.width=d.width;}state.drag=null;});
  window.addEventListener('lightek:timeline-time',event=>{const split=app.querySelector('[data-ew=split]'),clip=t()?.clips[editor().selected];if(split)split.disabled=!clip||event.detail.time<=clip.start||event.detail.time>=clip.start+length(clip);app.querySelectorAll('[data-edit-time]').forEach(el=>el.textContent=clock(event.detail.time));app.querySelectorAll('[data-ew-scrub]').forEach(el=>el.value=event.detail.time);app.querySelectorAll('.ew-playhead').forEach(el=>el.style.left=event.detail.time/duration()*100+'%');});
  window.addEventListener('lightek:timeline-stopped',()=>{const play=app.querySelector('[data-ew=play]');if(play)play.textContent='▶';});
  window.LightekStudioEdit={view,beforeRender,mount,renderInto,busy:()=>state.uploads.some(u=>['queued','uploading','registering'].includes(u.status))};
})();
