(() => {
  let state = {}, busy = false;
  const esc = value => E(String(value ?? ''));
  async function api(body, action = '') {
    const response = await fetch(`/api/lightek/pwa/youtube/posts/${state.id}${action}`, {method:body?'POST':'GET', credentials:'same-origin',
      headers:{Accept:'application/json', ...window.nevaeh.csrfHeaders(), ...(body?{'Content-Type':'application/json'}:{})}, ...(body?{body:JSON.stringify(body)}:{})});
    return window.nevaeh.parseResponse(response);
  }
  async function load() {
    const id=Number(location.hash.split('/')[2]);if(state.loading||state.id===id)return;state={id,loading:true};
    try{state.data=await api();}catch(e){state.error=e.message;}
    state.loading=false;if(location.hash.startsWith('#/youtube/'))render(1);
  }
  R.youtube = () => `<div class="wrap pwa-page"><a href="#/post/${Number(state.id)}">← Back to video</a><h1>Publish through Lightek YouTube</h1>
    ${state.error?`<p role="alert">${esc(state.error)}</p>`:''}${!state.data?'<p role="status">Loading…</p>':`
    <section class="pwa-post"><h2>${esc(state.data.post.title||'Your video')}</h2>${state.data.upload?`<p role="status">${esc(state.data.upload.status.replaceAll('_',' '))}</p>${! ['withdraw_pending','withdrawn'].includes(state.data.upload.status)?'<button class="btn" data-a="youtubeWithdraw">Remove from Lightek YouTube</button>':''}${state.data.upload.error_code?`<p>${esc(state.data.upload.error_code.replaceAll('_',' '))}</p>`:''}${state.data.upload.video_id?`<a href="https://www.youtube.com/watch?v=${esc(state.data.upload.video_id)}" target="_blank" rel="noopener noreferrer">Watch on YouTube</a>`:''}`:!state.data.enabled?'<p>Channel publishing is not open yet.</p>':`
    <p>Your original stays in your Lightek instance. Lightek uploads a copy to its central YouTube channel. After processing and public embedding are verified, the PWA plays that copy. YouTube may restrict, reject or demonetize a video; uploading does not guarantee view revenue.</p>
    <form data-youtube-consent><label><input name="consent" type="checkbox" required> I own or have all necessary rights, and authorize Lightek to publicly upload and distribute this video through its YouTube channel.</label>
    <label class="fld"><span>Is this video made for children?</span><select name="kids" required><option value="">Choose the accurate audience</option><option value="false">No</option><option value="true">Yes</option></select></label>
    <button class="btn p" ${busy?'disabled':''}>Submit original to Lightek YouTube</button></form>`}</section>`}<button class="btn" data-a="youtubeRefresh">Refresh publishing status</button></div>`;
  AF.youtube=load;
  A.youtubeWithdraw=async()=>{if(busy)return;busy=true;try{state.data.upload=(await api({},'/withdraw')).upload;}catch(e){state.error=e.message;}busy=false;render(1);};
  A.youtubeRefresh=()=>{state={};load();};
  document.addEventListener('submit',async event=>{
    if(!event.target.matches('[data-youtube-consent]'))return;event.preventDefault();if(busy)return;busy=true;
    const form=new FormData(event.target);
    try{const data=await api({consent:form.has('consent'),made_for_kids:form.get('kids')==='true'});state.data.upload=data.upload;state.error='';}catch(e){state.error=e.message;}
    busy=false;render(1);
  });
  addEventListener('lightek.bootstrap.ready',()=>{state={};});
})();
