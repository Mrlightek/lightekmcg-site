export function mountGenerationPanel(root,scene,onReady){
  const panel=document.createElement('section');panel.className='pwa-post';panel.dataset.generationPanel='';panel.innerHTML='<h3>Describe an asset. Put it on stage.</h3><p>Generate a 3D prop, save it in Library and fit it into this shot. Uses your configured Tripo account and its generation charges.</p><form><label class="fld">Asset description<textarea name="prompt" required minlength="3" maxlength="2000" rows="3" placeholder="A worn brass desk lamp with a green glass shade"></textarea></label><button class="btn p sm">Generate & stage</button><button type="button" class="btn sm" data-retry hidden>Resume processing</button></form><p role="status">Configure your provider in Dashboard → Studio & broadcasting.</p><img alt="Generated asset preview" hidden style="max-width:240px"><a class="btn sm" href="#/studio/library">Open Library</a>';
  root.querySelector('[data-spatial-canvas]').after(panel);let id=null,timer,disposed=false;const abort=new AbortController();
  const status=panel.querySelector('[role=status]'),submit=panel.querySelector('button'),retry=panel.querySelector('[data-retry]');
  const api=async body=>{const response=await fetch('/api/lightek/pwa/studio/generation',{method:'POST',credentials:'same-origin',signal:abort.signal,headers:{...window.nevaeh.csrfHeaders(),'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await response.json();if(!response.ok)throw Error(result.error||'Generation unavailable');return result;};
  const watch=async()=>{try{const result=await api({operation:'status',asset_id:id});if(disposed)return;
    status.textContent=result.error||({queued:'Queued for your instance',submitting:'Submitting to the 3D provider',generating:'Generating your model',downloading:'Downloading the model',optimizing:'Optimizing geometry and textures',staging:'Fitting the model into your shot',ready:'Your asset is saved in Library and staged in this shot.'}[result.generation?.phase]||result.status);
    if(result.thumbnail_url){const image=panel.querySelector('img');image.src=result.thumbnail_url;image.hidden=false;}
    if(result.status==='ready'){submit.disabled=false;sessionStorage.removeItem('studio-generation-'+scene.id);await onReady(result);return;}
    if(result.status==='failed'){submit.disabled=false;retry.hidden=!(result.generation?.task_id||result.generation?.phase==='configuration');return;}
    timer=setTimeout(watch,2000);
  }catch(error){if(!disposed){status.textContent=error.message;submit.disabled=false;}}};
  panel.querySelector('form').onsubmit=async event=>{event.preventDefault();submit.disabled=true;retry.hidden=true;
    try{const form=event.target;form.dataset.requestKey||=crypto.randomUUID();const result=await api({scene_id:scene.id,prompt:form.elements.prompt.value,request_key:form.dataset.requestKey});id=result.asset_id;sessionStorage.setItem('studio-generation-'+scene.id,String(id));delete form.dataset.requestKey;await watch();}catch(error){if(!disposed){status.textContent=error.message;submit.disabled=false;}}
  };
  retry.onclick=async()=>{retry.hidden=true;submit.disabled=true;try{await api({operation:'retry',asset_id:id});await watch();}catch(error){status.textContent=error.message;submit.disabled=false;}};
  const saved=sessionStorage.getItem('studio-generation-'+scene.id);if(saved){id=Number(saved);submit.disabled=true;void watch();}
  return {dispose(){disposed=true;clearTimeout(timer);abort.abort();panel.remove();}};
}
