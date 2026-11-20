(()=>{function boot(){const root=document.querySelector('[data-live-studio]'),desk=document.querySelector('[data-audience-desk]');if(!root||!desk||desk.dataset.wired)return;desk.dataset.wired='1';let timer,id,disposed=false;
 const q=s=>desk.querySelector(s);function line(list,name,text,comment=null){const li=document.createElement('li'),content=document.createElement('span');content.className='ll-comment-text';content.textContent=String(name).slice(0,120)+(text?': '+String(text).slice(0,2000):'');li.append(content);if(comment&&String(text||'').trim()){const button=document.createElement('button');button.type='button';button.textContent='Show on program';button.dataset.featureComment='';button.setAttribute('aria-label','Show comment from '+String(name).slice(0,80)+' on program');button.addEventListener('click',()=>root.dispatchEvent(new CustomEvent('lightek:feature-comment',{detail:comment})));li.append(button);}list.append(li);while(list.children.length>100)list.firstChild.remove();}
 async function poll(){if(!id||disposed)return;const current=id;try{const response=await fetch('/dashboard/live/'+current+'/audience',{credentials:'same-origin',headers:{Accept:'application/json'}});const data=await response.json();if(!response.ok)throw Error(data.error||'Audience unavailable.');if(current!==id||disposed)return;q('[data-audience-status]').textContent=data.viewer_count+' Lightek viewers · updated '+new Date(data.observed_at).toLocaleTimeString();q('[data-live-viewers]').replaceChildren();for(const person of data.viewers)line(q('[data-live-viewers]'),person.name||'Guest');q('[data-live-comments]').replaceChildren();for(const comment of data.comments)line(q('[data-live-comments]'),comment.name||'Guest',comment.text,{source:'lightek',name:comment.name,text:comment.text});}catch(e){if(current===id&&!disposed)q('[data-audience-status]').textContent=e.message;}finally{if(!disposed&&current===id)timer=setTimeout(poll,10000);}}
 const sockets = new Map();
 const socialElement = (field, source) => q('[data-social-' + field + '="' + source + '"]');

 function stopSocial(source) {
  const value = sockets.get(source);
  if (!value) return;
  sockets.delete(source);
  clearInterval(value.heartbeat);
  value.request.abort();
  value.ws?.close();
  socialElement('state', source).textContent = 'Disconnected';
  socialElement('count', source)?.replaceChildren();
  socialElement('people', source)?.replaceChildren();
 }

 async function connectSocial(source) {
  stopSocial(source);
  const state = socialElement('state', source);
  const feed = socialElement('feed', source);
  const counts = socialElement('count', source);
  const people = socialElement('people', source);
  const value = { request: new AbortController() };
  sockets.set(source, value);
  const current = () => sockets.get(source) === value;
  state.textContent = 'Connecting…';
  feed.replaceChildren();
  const countRows = new Map();
  const peopleRows = new Map();
  const seen = new Set();
  const clearPresence = () => {
   counts?.replaceChildren();
   people?.replaceChildren();
   countRows.clear();
   peopleRows.clear();
  };

  function remember(rows, list, key, label, limit) {
   if (!list) return;
   const row = rows.get(key) || document.createElement('li');
   row.textContent = label;
   rows.delete(key);
   rows.set(key, row);
   list.prepend(row);
   if (rows.size > limit) {
    const oldest = rows.keys().next().value;
    rows.get(oldest).remove();
    rows.delete(oldest);
   }
  }

  try {
   const response = await fetch('/dashboard/live/audience-connection', {
    method: 'POST', credentials: 'same-origin', signal: value.request.signal,
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]')?.content || '' },
    body: JSON.stringify({ source })
   });
   const data = await response.json();
   if (!current()) return;
   if (!response.ok) throw Error(data.error || 'Save your connection settings first.');
   const ws = value.ws = new WebSocket((location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + location.host + data.cable_path, ['actioncable-v1-json']);
   const identifier = JSON.stringify({ channel: 'StudioAudienceChannel', ticket: data.ticket });
   ws.onmessage = event => {
    if (!current()) return;
    try {
     const packet = JSON.parse(event.data);
     if (packet.type === 'welcome') return ws.send(JSON.stringify({ command: 'subscribe', identifier }));
     if (packet.type === 'reject_subscription') {
      stopSocial(source);
      state.textContent = 'Audience reader unavailable. Check deployment or close another Live Studio connection.';
      return;
     }
     if (packet.type === 'confirm_subscription') {
      value.heartbeat = setInterval(() => {
       if (ws.readyState === 1) ws.send(JSON.stringify({ command: 'message', identifier, data: JSON.stringify({ action: 'heartbeat' }) }));
      }, 15000);
      return;
     }
     const d = packet.message;
     if (!d) return;
     if (d.type === 'status') {
      if (['reader_stopped', 'expired'].includes(d.status)) stopSocial(source);
      if (d.status !== 'connected') clearPresence();
      state.textContent = d.status === 'signing_or_rate_limit'
       ? 'Signing service access / rate limit. Configure a provider key or use SSN.'
       : String(d.status).replaceAll('_', ' ');
      return;
     }
     const platform = String(d.platform || (source === 'tiktok' ? 'TikTok' : 'Social')).slice(0, 40);
     if (Number.isSafeInteger(d.viewer_count) && d.viewer_count >= 0) {
      remember(countRows, counts, platform, platform + ' · ' + d.viewer_count + ' viewers · ' + new Date().toLocaleTimeString(), 30);
     }
     if (d.id) {
      const key = JSON.stringify([platform, d.type, d.id, d.repeat_count, d.repeat_end]);
      if (seen.has(key)) return;
      seen.add(key);
      if (seen.size > 500) seen.delete(seen.values().next().value);
     }
     if (d.handle && ['member', 'chat', 'gift', 'social'].includes(d.type)) {
      const name = d.name || d.handle;
      const handle = d.handle !== name && source === 'tiktok' ? ' (@' + d.handle + ')' : '';
      remember(peopleRows, people, JSON.stringify([platform, d.handle]), platform + ' · ' + name + handle, 30);
     }
     if (d.type === 'viewers' || d.type === 'like') return;
     const comment = d.type === 'chat' && typeof d.text === 'string' && d.text.trim()
      ? { source, name: d.name, text: d.text, platform: d.platform }
      : null;
     line(feed, platform + ' · ' + (d.name || 'Viewer'), d.text || (d.type === 'gift' ? 'Gift received' : 'Activity'), comment);
    } catch (error) {
     state.textContent = error.message;
    }
   };
   ws.onclose = () => {
    if (!current()) return;
    stopSocial(source);
    state.textContent = 'Disconnected · reconnect when ready';
   };
   ws.onerror = () => { if (current()) state.textContent = 'Audience connection failed'; };
  } catch (error) {
   if (!current()) return;
   stopSocial(source);
   state.textContent = error.message;
  }
 }
 desk.querySelectorAll('[data-social-connect]').forEach(button=>button.onclick=()=>connectSocial(button.dataset.socialConnect));desk.querySelectorAll('[data-social-stop]').forEach(button=>button.onclick=()=>stopSocial(button.dataset.socialStop));
 root.addEventListener('lightek:broadcast-session',event=>{clearTimeout(timer);id=event.detail.id;q('[data-audience-status]').textContent='Loading this broadcast’s audience…';q('[data-live-comments]').replaceChildren();q('[data-live-viewers]').replaceChildren();poll();});root.addEventListener('lightek:room-chat',event=>line(q('[data-session-messages]'),event.detail.name,event.detail.text,{source:'room',name:event.detail.name,text:event.detail.text}));const stop=()=>{disposed=true;clearTimeout(timer);for(const source of sockets.keys())stopSocial(source);};window.addEventListener('pagehide',stop,{once:true});document.addEventListener('turbo:before-cache',stop,{once:true});}
 document.addEventListener('turbo:load',boot);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();})();
