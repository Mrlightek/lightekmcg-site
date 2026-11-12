/* Lightek storage and media bridge. Editing is provided by miniPaint/Movie Masher. */
(() => {
  const host=document.querySelector('[data-editor-kind]');if(!host)return;
  const kind=host.dataset.editorKind,site=host.dataset.siteId,base=host.dataset.editorBase;
  const initial=JSON.parse(host.querySelector('[data-editor-document]').textContent);
  const status=host.querySelector('[data-editor-status]');
  let editor,photo,dirty=false,busy=true,revision=Number(host.dataset.lockVersion),disposed=false;
  let lastDocument=initial.document,exportKey=null;
  const key=()=>globalThis.crypto?.randomUUID?.()||Array.from(crypto.getRandomValues(new Uint8Array(16)),n=>n.toString(16).padStart(2,'0')).join('');
  const message=(text,error=false)=>{status.textContent=text;status.setAttribute('role',error?'alert':'status');};
  const mark=()=>{dirty=true;exportKey=null;if(!busy)message('Unsaved changes');};
  const surface=host.querySelector('iframe,#lightek-video-editor');surface.inert=true;
  host.querySelectorAll('[data-editor-action],[data-editor-import],[data-editor-restore],[data-editor-asset]').forEach(control=>control.disabled=true);
  const ready=()=>{busy=false;dirty=false;surface.inert=false;host.dataset.editorReady='true';host.querySelectorAll('[data-editor-action],[data-editor-import],[data-editor-restore],[data-editor-asset]').forEach(control=>control.disabled=false);};
  const endpoint=(suffix)=>`${base}${suffix}?site_id=${encodeURIComponent(site)}`;
  async function request(suffix,{body,method='POST'}={}){
    const multipart=body instanceof FormData;
    const response=await fetch(endpoint(suffix),{method,credentials:'same-origin',headers:{'Accept':'application/json','X-CSRF-Token':host.dataset.csrfToken,...(multipart?{}:{'Content-Type':'application/json'})},body:multipart?body:JSON.stringify(body)});
    let data;try{data=await response.json();}catch{throw Error(response.status===413?'This file exceeds the server upload limit.':'The server did not return a Studio response. Your work is still open; download a project backup.');}
    if(!response.ok)throw Error(data.error||`Studio request failed (${response.status})`);return data;
  }
  async function run(action){if(busy)return [];busy=true;const surface=host.querySelector('iframe,#lightek-video-editor');surface.inert=true;host.querySelectorAll('[data-editor-action]').forEach(button=>button.disabled=true);try{return await action();}catch(error){message(error.message,true);return [];}finally{busy=false;surface.inert=false;host.querySelectorAll('[data-editor-action]').forEach(button=>button.disabled=false);}}
  async function snapshot(){
    if(kind==='photo'){if(!photo?.FileSave)throw Error('Photo Studio is still opening');return JSON.parse(photo.FileSave.export_as_json());}
    if(!editor?.selection?.mash)throw Error('Video Studio is still opening');
    const result=await editor.dataPutRequest();
    return JSON.parse(JSON.stringify({mash:{...result.mash,width:initial.width,height:initial.height},definitions:editor.definitions.filter(definition=>definition.id.startsWith('lightek.media.')).map(definition=>definition.toJSON())}));
  }
  async function save(){
    const source=await snapshot();const result=await request('/document',{method:'PUT',body:{document:source,lock_version:revision}});
    revision=result.lock_version;host.dataset.lockVersion=revision;dirty=false;lastDocument=source;editor?.saved();message('Project saved to Lightek');return source;
  }
  function download(blob,name){const url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),30000);}
  async function backup(){download(new Blob([JSON.stringify(await snapshot())],{type:'application/json'}),`lightek-${kind}-project.json`);message('Project backup downloaded. Save project to keep a copy in Lightek.');}
  async function dimensions(file){
    const url=URL.createObjectURL(file);
    try{return await probe(url,file.type.split('/')[0]);}finally{URL.revokeObjectURL(url);}
  }
  function probe(url,type){return new Promise((resolve,reject)=>{
    const media=type==='image'?new Image():document.createElement(type==='audio'?'audio':'video');let timer;
    const done=()=>{clearTimeout(timer);resolve({width:media.naturalWidth||media.videoWidth||0,height:media.naturalHeight||media.videoHeight||0,duration:media.duration||0});if(type!=='image'){media.removeAttribute('src');media.load();}};
    media[type==='image'?'onload':'onloadedmetadata']=done;media.onerror=()=>{clearTimeout(timer);reject(Error('This browser cannot preview that media format. Try PNG/JPEG, MP4 H.264/AAC or WebM.'));};timer=setTimeout(()=>reject(Error('Media preview timed out. Try a smaller file or another format.')),30000);media.src=url;
  });}
  function definition(id,name,type,url,info){return {id:`lightek.media.${id}`,label:name,type,url:new URL(url,location.origin).href,source:new URL(url,location.origin).href,...(type==='image'?{}:{audio:true,audioUrl:new URL(url,location.origin).href,duration:info.duration}),...(info.width?{width:info.width,height:info.height,previewSize:{width:info.width,height:info.height}}:{})};}
  async function addFiles(files,index={track:0}){
    const results=[];
    for(const file of files){
      if(file.size>250*1024*1024)throw Error('Choose a file smaller than 250 MB');
      const type=file.type.split('/')[0];if(!['image','audio','video'].includes(type))throw Error('Choose an image, audio or video file');
      if(kind==='photo'){
        if(type!=='image')throw Error('Photo Studio accepts images. Open Video Studio for video and audio.');
        const ids=new Set(photo.AppConfig.layers.map(layer=>layer.id));
        await photo.FileOpen.open_handler({target:{files:[file]}});
        await new Promise((resolve,reject)=>{const started=Date.now();const check=()=>{if(photo.AppConfig.layers.some(layer=>!ids.has(layer.id)&&layer.type==='image'&&layer.link?.complete))return resolve();if(Date.now()-started>30000)return reject(Error('Could not prepare this image. Try PNG or JPEG.'));setTimeout(check,50);};check();});
        mark();continue;
      }
      message(`Importing ${file.name}…`);const info=await dimensions(file);
      const body=new FormData();body.append('file',file);body.append('request_key',key());
      const result=await request('/media',{body});
      const added=await editor.add(definition(result.id,file.name,type,result.url,info),index);
      results.push(...added);mark();
    }
    message(kind==='photo'?'Image added as an editable layer.':'Media added. Edit its clip in the timeline.');return results;
  }
  async function photoBlob(){
    const canvas=document.createElement('canvas'),size=photo.Layers.get_dimensions();canvas.width=size.width;canvas.height=size.height;
    photo.Layers.convert_layers_to_canvas(canvas.getContext('2d'));
    return new Promise((resolve,reject)=>canvas.toBlob(blob=>blob?resolve(blob):reject(Error('Could not export this image')),'image/png'));
  }
  function showExport(data){
    const area=host.querySelector('[data-editor-exports]');let row=area.querySelector(`[data-operation="${Number(data.id)}"]`);
    if(!row){row=document.createElement('article');row.dataset.operation=data.id;area.prepend(row);}row.replaceChildren();
    const text=document.createElement('strong');text.textContent=`Export #${data.id} · ${data.status}`;row.append(text);
    if(data.error){const error=document.createElement('p');error.setAttribute('role','alert');error.textContent=data.error;row.append(error);}
    for(const artifact of data.artifacts||[]){const link=document.createElement('a');link.href=artifact.url;link.textContent=`Download ${artifact.filename}`;link.target='_blank';link.rel='noopener';row.append(link);}
  }
  async function poll(id){
    if(disposed)return;
    try{const data=await request(`/exports/${id}`,{method:'GET'});showExport(data);if(['pending','running'].includes(data.status)){setTimeout(()=>poll(id),2500);}else message(data.status==='completed'?'Export ready. Download it below or find it in your Lightek media library.':data.error||'Export failed. Your saved project is safe; try Export again.',data.status!=='completed');}
    catch(error){message(`${error.message} Reopen this project to check export status.`,true);}
  }
  host.querySelectorAll('[data-editor-action]').forEach(button=>button.addEventListener('click',()=>{
    if(button.dataset.editorAction==='import'){host.querySelector('[data-editor-import]').click();return;}
    return run(async()=>{
    if(button.dataset.editorAction==='save')return save();
    if(button.dataset.editorAction==='backup')return backup();
    const source=await save();exportKey ||= key();
    let body={request_key:exportKey,lock_version:revision};
    if(kind==='photo'){const form=new FormData();form.append('request_key',exportKey);form.append('lock_version',revision);form.append('image',await photoBlob(),'artwork.png');body=form;}
    message('Queueing export…');const data=await request('/export',{body});showExport(data);poll(data.id);exportKey=null;
  });}));
  const saveShortcut=event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='s'){event.preventDefault();event.stopImmediatePropagation();run(save);}};
  document.addEventListener('keydown',saveShortcut,true);
  host.querySelector('[data-editor-import]').addEventListener('change',event=>{const files=Array.from(event.target.files);event.target.value='';run(()=>addFiles(files));});
  host.querySelector('[data-editor-restore]').addEventListener('change',event=>{
    const file=event.target.files[0];event.target.value='';if(!file)return;
    if(dirty&&!confirm('Replace your unsaved work with this backup? Download a project backup first if you want to keep both.'))return;
    run(async()=>{
      if(file.size>24*1024*1024)throw Error('Choose a project backup smaller than 24 MB');
      let source;try{source=JSON.parse(await file.text());}catch{throw Error('Choose a valid Lightek project JSON backup');}
      if(kind==='photo'?!source.info:!source.mash)throw Error(`This backup belongs to a different editor. Open ${kind==='photo'?'Video':'Photo'} Studio.`);
      await request('/document',{method:'PUT',body:{document:source,lock_version:revision}});dirty=false;busy=false;location.reload();
    });
  });
  host.querySelectorAll('[data-editor-asset]').forEach(button=>button.addEventListener('click',()=>run(async()=>{
    if(kind==='photo'){if(button.dataset.type!=='image')throw Error('Choose a still image for Photo Studio');const response=await fetch(button.dataset.url);if(!response.ok)throw Error('Media is unavailable');await addFiles([new File([await response.blob()],button.dataset.name,{type:'image/png'})]);}
    else{const info=await probe(button.dataset.url,button.dataset.type);await editor.add(definition(button.dataset.editorAsset,button.dataset.name,button.dataset.type,button.dataset.url,info),{track:0});mark();}
  })));
  async function open(){
    if(kind==='photo'){
      const frame=host.querySelector('iframe');await new Promise((resolve,reject)=>{const started=Date.now();const check=()=>{if(frame.contentWindow?.FileSave)return resolve();if(Date.now()-started>30000)return reject(Error('Photo Studio did not finish loading. Reload the page; your saved project stays in Lightek.'));setTimeout(check,50);};check();});photo=frame.contentWindow;
      photo.AppConfig.pixabay_key='';photo.AppConfig.google_webfonts_key='';photo.AppConfig.enable_autoresize_by_default=false;
      if(initial.document)await photo.FileOpen.load_json(initial.document);
      else{const source=JSON.parse(photo.FileSave.export_as_json());source.info.width=initial.width;source.info.height=initial.height;await photo.FileOpen.load_json(source);}
      photo.document.addEventListener('input',mark);photo.document.addEventListener('pointerup',mark);
      photo.document.addEventListener('keydown',saveShortcut,true);
      photo.document.addEventListener('keydown',event=>{if(['Delete','Backspace'].includes(event.key)||((event.ctrlKey||event.metaKey)&&['z','y','v','x'].includes(event.key.toLowerCase())))mark();});
      ready();
      message('Photo Studio ready. Use File → Open or Import media to add an image.');
    }else{
      const {Core,mount}=window.LightekMovieMasher;
      const font=Core.Defined.fromId('com.moviemasher.font.default');font.source=font.url=new URL('/lightek/editors/video/font.ttf',location.origin).href;
      const source=initial.document||{mash:{label:host.querySelector('h1').textContent,width:initial.width,height:initial.height,quantize:30,tracks:[{clips:[]}]},definitions:[]};
      for(const d of source.definitions||[])for(const k of ['url','source','audioUrl'])if(d[k])d[k]=new URL(d[k],location.origin).href;
      mount(host.querySelector('#lightek-video-editor'),source,instance=>{
        editor=instance;editor.addFiles=(files,index)=>run(()=>addFiles(Array.from(files),index||{track:0}));
        host.querySelector('#lightek-video-editor').addEventListener('input',mark);host.querySelector('#lightek-video-editor').addEventListener('pointerup',mark);
        const check=()=>{if(editor.selection?.mash){ready();message('Video Studio ready. Import media to add a clip to your timeline.');}else setTimeout(check,50);};check();
      });
    }
    host.querySelectorAll('[data-operation]').forEach(row=>poll(Number(row.dataset.operation)));
  }
  window.addEventListener('beforeunload',event=>{if(dirty||busy){event.preventDefault();event.returnValue='';}});
  window.addEventListener('pagehide',()=>{disposed=true;});
  // Exposed for integration acceptance and host extensions, not a second editor.
  window.LightekEditors={snapshot,save,addFiles,get editor(){return editor;},get photo(){return photo;},get dirty(){return dirty;}};
  open().catch(error=>message(error.message,true));
})();
