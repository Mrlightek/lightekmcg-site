(() => {
  function boot(){
    const dialog=document.querySelector('[data-nevaeh-help-dialog]');
    if(!dialog||dialog.dataset.ready)return;dialog.dataset.ready='1';
    const title=dialog.querySelector('#nv-help-title'),body=dialog.querySelector('[data-nevaeh-help-body]'),link=dialog.querySelector('[data-nevaeh-help-document]');
    let activeRequest=null;
    dialog.querySelector('[data-nevaeh-help-close]').addEventListener('click',()=>dialog.close());
    document.addEventListener('click',async event=>{
      const button=event.target.closest('[data-nevaeh-help]');if(!button)return;
      event.preventDefault();event.stopPropagation();activeRequest?.abort();activeRequest=new AbortController();
      title.textContent='Loading guide…';body.textContent='';link.hidden=true;if(!dialog.open)dialog.showModal();
      try{
        const url=new URL(`/employee/nevaeh/help/${encodeURIComponent(button.dataset.nevaehHelp)}`,location.origin);
        if(button.dataset.nevaehField)url.searchParams.set('field',button.dataset.nevaehField);
        const response=await fetch(url,{credentials:'same-origin',headers:{Accept:'application/json'},signal:activeRequest.signal});
        if(!response.ok)throw new Error('This guide is unavailable for your account.');
        const guide=await response.json();title.textContent=guide.title;const p=document.createElement('p');p.textContent=guide.body;body.replaceChildren(p);for(const doc of guide.related_documents||[]){if(doc.url?.startsWith('/')&&!doc.url.startsWith('//')){const anchor=document.createElement('a');anchor.href=doc.url;anchor.textContent=doc.title;body.append(anchor);}}
        if(guide.document_url?.startsWith('/')&&!guide.document_url.startsWith('//')){link.href=guide.document_url;link.hidden=false;}
      }catch(error){if(error.name!=='AbortError'){title.textContent='Guide unavailable';body.textContent=error.message;}}
    });
    const attach=()=>document.querySelectorAll('.dd-content label,[data-help-scope] label').forEach(label=>{
      if(label.querySelector('[data-nevaeh-help]')||label.closest('[data-no-help],dialog'))return;
      const control=label.querySelector('input:not([type=hidden]),textarea,select');if(!control)return;
      const scope=label.closest('[data-help-scope]')?.dataset.helpScope||document.querySelector('[data-nevaeh-center] .nc-tabs .active')?.getAttribute('href')?.split('tab=')[1]?.split('&')[0]||'library';
      const field=(label.firstChild?.textContent||control.name||'Field').trim().slice(0,120);
      const button=document.createElement('button');button.type='button';button.className='nv-info';button.textContent='i';button.dataset.nevaehHelp=scope;button.dataset.nevaehField=field;button.setAttribute('aria-label',`${field}: tutorial`);button.setAttribute('aria-haspopup','dialog');let anchor=control;while(anchor.parentElement!==label)anchor=anchor.parentElement;label.insertBefore(button,anchor);
    });
    attach();let pending=false;const observer=new MutationObserver(()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;attach();});});
    observer.observe(document.querySelector('.dd-content')||document.querySelector('[data-help-scope]')||document.body,{childList:true,subtree:true});
    document.addEventListener('turbo:before-cache',()=>observer.disconnect(),{once:true});
  }
  document.addEventListener('DOMContentLoaded',boot);document.addEventListener('turbo:load',boot);boot();
})();
