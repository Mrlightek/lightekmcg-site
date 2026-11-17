/* Only references live centrally. Fetch public content from its source instance. */
(() => {
  const cache = new Map(), pending = new Map();
  const esc = v => E(String(v ?? ''));
  const idPattern = /^[A-Za-z0-9_-]{11}$/;
  function media(post, origin) {
    const youtube = post.metadata?.youtube_video_id;
    if(idPattern.test(youtube || ''))return `<p>YouTube</p><iframe class="pwa-youtube" title="${esc(post.title||'YouTube video')}" src="https://www.youtube.com/embed/${youtube}" loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" allowfullscreen referrerpolicy="strict-origin-when-cross-origin"></iframe><p><a href="https://www.youtube.com/watch?v=${youtube}" target="_blank" rel="noopener noreferrer">Watch on YouTube</a></p>`;
    if(post.metadata?.youtube_upload_key)return '<p role="status">Preparing the creator’s YouTube version…</p>';
    return (Array.isArray(post.media)?post.media:[]).slice(0,8).map(file=>{
      if(typeof file.url!=='string'||!/^\/api\/lightek\/pwa\/posts\/\d+\/media\/\d+$/.test(file.url))return '';
      const url=esc(origin+file.url),type=String(file.content_type||'');
      if(type.startsWith('image/'))return `<img class="pwa-media" src="${url}" loading="lazy" alt="${esc(post.title||file.filename)}">`;
      if(type.startsWith('video/'))return `<video class="pwa-media" src="${url}" controls playsinline preload="none"></video>`;
      if(type.startsWith('audio/'))return `<audio class="pwa-media" src="${url}" controls preload="none"></audio>`;
      return '';
    }).join('');
  }
  async function hydrate(node) {
    const raw=node.dataset.remoteContent;
    try {
      const url=new URL(raw);
      if(url.protocol!=='https:'||url.username||url.password||!/^\/api\/lightek\/network\/posts\/\d+$/.test(url.pathname)||url.search||url.hash)throw new Error('Invalid content reference');
      let record=cache.get(raw);
      if(!record||Date.now()-record.at>15000){
        if(!pending.has(raw))pending.set(raw,(async()=>{
          const response=await fetch(raw,{credentials:'omit',redirect:'error',headers:{Accept:'application/json'},signal:AbortSignal.timeout(8000)});
          if(!response.ok)throw new Error('Source unavailable');
          const text=await response.text();if(text.length>500000)throw new Error('Source response is too large');
          const post=JSON.parse(text);
          if(post.visibility!=='public'||post.audience!=='everyone'||post.metadata?.remote_content)throw new Error('Content is no longer public');
          const result={at:Date.now(),post};cache.set(raw,result);if(cache.size>100)cache.delete(cache.keys().next().value);
          return result;
        })().finally(()=>pending.delete(raw)));
        record=await pending.get(raw);
      }
      const p=record.post;
      node.innerHTML=`<p class="pwa-post-body">${esc(p.content)}</p>${media(p,url.origin)}<p><a class="btn sm" href="${esc(url.origin)}/lightek/index.html#/post/${Number(p.id)}">Open original post</a></p>`;
      node.dataset.remoteLoaded='true';
    }catch(e){node.innerHTML='<p class="pwa-empty">The source instance is unavailable, or this post is no longer public.</p>';node.dataset.remoteLoaded='true';}
  }
  const observer=new IntersectionObserver(entries=>{for(const entry of entries)if(entry.isIntersecting){observer.unobserve(entry.target);hydrate(entry.target);}},{rootMargin:'200px'});
  function scan(){for(const node of document.querySelectorAll('[data-remote-content]:not([data-remote-observed])')){node.dataset.remoteObserved='true';observer.observe(node);}}
  new MutationObserver(scan).observe(document.getElementById('app'),{childList:true,subtree:true});
  scan();
})();
