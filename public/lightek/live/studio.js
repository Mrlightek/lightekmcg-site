(()=>{
function boot(){
 const root=document.querySelector('[data-live-studio]');if(!root||root.dataset.wired)return;root.dataset.wired='1';
 const q=s=>root.querySelector(s),preview=q('[data-preview]'),badge=q('[data-state]'),status=q('[data-status]'),error=q('[data-error]');
 let screen,camera,mic,audio,mixer,micNode,gain,analyser,silent,program,canvas,paintTimer,clockTimer,ws,recorder,identifier,active=false,stopping=false,holding=false,muted=true,queue=[],pending=null,sequence=0,queuedBytes=0,started=0,connectTimer,transportPhase='idle',cameraBusy=false,captureGeneration=0;
 const source=document.createElement('video');source.muted=true;source.playsInline=true;
 const cameraVideo=document.createElement('video');cameraVideo.muted=true;cameraVideo.playsInline=true;
 const supported=!!(window.isSecureContext&&navigator.mediaDevices?.getUserMedia&&window.MediaRecorder&&HTMLCanvasElement.prototype.captureStream);
 const live=stream=>!!stream?.getVideoTracks().some(track=>track.readyState==='live');
 function missingSource(){const mode=q('[data-layout]').value;if(mode!=='screen'&&!live(camera))return 'Enable your camera first.';if(mode!=='camera'&&!live(screen))return 'Choose a screen or window first.';return '';}
 function sourceStatus(){q('[data-source-status]').textContent=[live(screen)?'Screen selected':null,live(camera)?camera.getVideoTracks()[0].label||'Camera enabled':null].filter(Boolean).join(' · ')||'No video source selected';}
 function message(text){error.textContent=text||'';error.hidden=!text;}
 function controls(){q('[data-start]').disabled=active||!supported||root.dataset.encoder!=='ready';q('[data-stop]').disabled=!active||stopping;q('[data-title]').disabled=active;q('[data-destination]').disabled=active;}
 function micUI(){q('[data-mic]').setAttribute('aria-pressed',String(!muted));q('[data-mic]').textContent=muted?'Enable microphone':'Mute microphone';q('[data-mic-status]').textContent=holding?'Muted during holding screen':muted?'Microphone off':'Microphone on';if(gain)gain.gain.value=muted||holding?0:1;}
 function hold(value){holding=value;q('[data-hold]').setAttribute('aria-pressed',String(value));q('[data-hold]').textContent=value?'Resume screen':'Holding screen';micUI();}
 async function ensureProgram(){
  if(program){await audio.resume();return;}
  audio=new (window.AudioContext||window.webkitAudioContext)();mixer=audio.createMediaStreamDestination();
  silent=audio.createOscillator();const silence=audio.createGain();silence.gain.value=0;silent.connect(silence).connect(mixer);silent.start();
  canvas=document.createElement('canvas');canvas.width=1280;canvas.height=720;const ctx=canvas.getContext('2d');
  function paint(){ctx.fillStyle='#0b121b';ctx.fillRect(0,0,1280,720);
   const mode=q('[data-layout]').value,video=mode==='camera'?cameraVideo:source,selected=mode==='camera'?camera:screen;
   if(!holding&&live(selected)&&video.readyState>=2){const ratio=Math.min(1280/video.videoWidth,720/video.videoHeight),w=video.videoWidth*ratio,h=video.videoHeight*ratio;ctx.drawImage(video,(1280-w)/2,(720-h)/2,w,h);
    if(mode==='combined'&&live(camera)&&cameraVideo.readyState>=2){ctx.fillStyle='#b5f58b';ctx.fillRect(916,496,328,188);ctx.fillStyle='#0b121b';ctx.fillRect(920,500,320,180);const r=Math.min(320/cameraVideo.videoWidth,180/cameraVideo.videoHeight),cw=cameraVideo.videoWidth*r,ch=cameraVideo.videoHeight*r;ctx.drawImage(cameraVideo,920+(320-cw)/2,500+(180-ch)/2,cw,ch);}
   }
   else{ctx.fillStyle='#b5f58b';ctx.font='22px sans-serif';ctx.fillText('LIGHTEK / LIVE',90,110);ctx.fillStyle='#f2f5fa';ctx.font='bold 56px sans-serif';ctx.fillText('Back in a moment.',90,340);ctx.fillStyle='#a7b4c6';ctx.font='24px sans-serif';ctx.fillText('Building Lightek. Stay with us.',90,390);}
   if(analyser){const bins=new Uint8Array(analyser.fftSize);analyser.getByteTimeDomainData(bins);const level=Math.sqrt(bins.reduce((sum,v)=>sum+((v-128)/128)**2,0)/bins.length);q('[data-meter]').value=muted||holding?0:Math.min(1,level*4);}
  }
  paint();paintTimer=setInterval(paint,1000/24);program=canvas.captureStream(24);mixer.stream.getAudioTracks().forEach(track=>program.addTrack(track));preview.srcObject=program;await preview.play();q('[data-placeholder]').hidden=true;await audio.resume();
 }
 async function share(){try{
  if(!supported||!navigator.mediaDevices.getDisplayMedia)throw Error('This browser does not support screen capture. You can use Camera only, or choose a compatible Firefox or Chrome browser over HTTPS.');
  const next=await navigator.mediaDevices.getDisplayMedia({video:{frameRate:{ideal:24,max:24},width:{ideal:1280},height:{ideal:720}},audio:false});
  const previous=screen;screen=next;source.srcObject=screen;await source.play();previous?.getTracks().forEach(track=>track.stop());
  const track=screen.getVideoTracks()[0];track.addEventListener('ended',()=>{if(screen?.getVideoTracks()[0]===track){if(q('[data-layout]').value!=='camera')hold(true);sourceStatus();}});
  sourceStatus();await ensureProgram();message('');status.textContent=active?'Screen selected. Use Resume screen when ready.':'Preview ready. Choose a destination and start when ready.';
 }catch(e){message(e.name==='NotAllowedError'?'Screen capture was not allowed. Choose screen again to grant permission.':e.message);}}
 async function enableCamera(){if(cameraBusy)return;cameraBusy=true;q('[data-camera]').disabled=true;const generation=captureGeneration;try{
  const previous=camera,choice=q('[data-camera-device]').value;
  const next=await navigator.mediaDevices.getUserMedia({video:{width:{ideal:640},height:{ideal:360},frameRate:{ideal:24,max:24},...(choice?{deviceId:{exact:choice}}:{facingMode:'user'})},audio:false});
  if(generation!==captureGeneration){next.getTracks().forEach(track=>track.stop());return;}
  camera=next;cameraVideo.srcObject=camera;await cameraVideo.play();previous?.getTracks().forEach(track=>track.stop());
  const track=camera.getVideoTracks()[0];track.addEventListener('ended',()=>{if(camera?.getVideoTracks()[0]===track){if(q('[data-layout]').value!=='screen')hold(true);q('[data-camera]').setAttribute('aria-pressed','false');q('[data-camera]').textContent='Enable camera';sourceStatus();}});
  if(!previous)q('[data-layout]').value=live(screen)?'combined':'camera';
  let devices=[];try{devices=await navigator.mediaDevices.enumerateDevices();}catch{}const select=q('[data-camera-device]');select.replaceChildren(new Option('System default camera',''));devices.filter(device=>device.kind==='videoinput').forEach((device,index)=>select.add(new Option(device.label||'Camera '+(index+1),device.deviceId)));const preferred=track.getSettings().deviceId||choice;select.value=[...select.options].some(option=>option.value===preferred)?preferred:'';
  q('[data-camera]').setAttribute('aria-pressed','true');q('[data-camera]').textContent='Disable camera';sourceStatus();await ensureProgram();message('');status.textContent=active?'Camera ready. Check the preview before resuming.':'Camera preview ready. Enable your microphone when needed.';
 }catch(e){message(e.name==='NotAllowedError'?'Camera access was not allowed. Allow Camera for this site in Firefox and macOS privacy settings, then try again.':e.name==='NotFoundError'?'No camera was found. Connect a camera and try again.':'The camera could not be opened. Close other apps using it or select another camera.');}finally{cameraBusy=false;q('[data-camera]').disabled=false;}}
 function disableCamera(){const previous=camera;camera=null;previous?.getTracks().forEach(track=>track.stop());cameraVideo.srcObject=null;q('[data-camera]').setAttribute('aria-pressed','false');q('[data-camera]').textContent='Enable camera';if(q('[data-layout]').value==='combined')q('[data-layout]').value='screen';else if(active&&q('[data-layout]').value==='camera')hold(true);sourceStatus();}
 async function toggleMic(){try{await ensureProgram();if(!mic){mic=await navigator.mediaDevices.getUserMedia({audio:{echoCancellation:true,noiseSuppression:true},video:false});micNode=audio.createMediaStreamSource(mic);gain=audio.createGain();analyser=audio.createAnalyser();analyser.fftSize=256;micNode.connect(analyser);micNode.connect(gain).connect(mixer);mic.getAudioTracks()[0].addEventListener('ended',()=>{muted=true;micUI();});}muted=!muted;micUI();message('');}catch(e){message('Microphone could not be enabled. Check browser and macOS microphone permissions.');}}
 function send(action,data={}){if(ws?.readyState!==WebSocket.OPEN)throw Error('Broadcast connection is closed.');ws.send(JSON.stringify({command:'message',identifier,data:JSON.stringify({action,...data})}));}
 async function pump(){
  if(pending||!active)return;
  if(!queue.length){if(stopping){send('stop');status.textContent='Finishing server output…';}return;}
  pending={blob:queue.shift(),sequence:sequence++};queuedBytes-=pending.blob.size;
  const entry=pending;
  try{const bytes=new Uint8Array(await entry.blob.arrayBuffer());if(!active||pending!==entry)return;let raw='';for(let i=0;i<bytes.length;i+=32768)raw+=String.fromCharCode(...bytes.subarray(i,i+32768));send('chunk',{sequence:entry.sequence,live_chunk:btoa(raw)});}catch(e){fail(e.message);}
 }
 function finish(text){active=false;stopping=false;clearTimeout(connectTimer);clearInterval(clockTimer);if(recorder?.state!=='inactive')recorder?.stop();queue=[];pending=null;queuedBytes=0;ws?.close();badge.textContent='Preview only';badge.dataset.active='false';status.textContent=text;controls();}
 function fail(text){message(text);finish('Session stopped. Preview stays local.');}
 function startRecorder(){
  if(!active||stopping)return;
  clearTimeout(connectTimer);const mime=['video/webm;codecs=vp8,opus','video/webm;codecs=vp9,opus','video/webm'].find(type=>MediaRecorder.isTypeSupported(type));
  if(!mime)return fail('This browser cannot encode WebM screen capture. Use Firefox or Chrome.');
  recorder=new MediaRecorder(program,{mimeType:mime,videoBitsPerSecond:1400000,audioBitsPerSecond:96000});
  recorder.addEventListener('dataavailable',event=>{if(!event.data.size||!active)return;if(event.data.size>1048576||queuedBytes+event.data.size+(pending?.blob.size||0)>4194304)return fail('The connection cannot keep up with capture. Session stopped; start a new test.');queue.push(event.data);queuedBytes+=event.data.size;pump();});
  recorder.addEventListener('stop',()=>{if(active)pump();});recorder.addEventListener('error',()=>fail('The browser recorder stopped unexpectedly.'));
  recorder.start(500);started=Date.now();clockTimer=setInterval(()=>{const elapsed=Math.floor((Date.now()-started)/1000);q('[data-clock]').textContent=String(Math.floor(elapsed/60)).padStart(2,'0')+':'+String(elapsed%60).padStart(2,'0');},1000);
  status.textContent='Connected. Waiting for encoded output…';
 }
 async function start(){
  if(active)return;if(missingSource())return message(missingSource());
  const destination=q('[data-destination]').value;
  if(destination==='tiktok'&&!window.confirm('Start sending this preview and microphone to your configured TikTok destination?'))return;
  active=true;stopping=false;queue=[];pending=null;sequence=0;queuedBytes=0;q('[data-download]').hidden=true;message('');controls();status.textContent='Connecting to the Lightek broadcaster…';
  try{
   await ensureProgram();if(!active)return;const response=await fetch(root.dataset.createUrl,{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]')?.content||''},body:JSON.stringify({title:q('[data-title]').value,destination})});
   const session=await response.json();if(!active)return;if(!response.ok)throw Error(session.error||'Could not create the live session.');
   identifier=JSON.stringify({channel:'StudioBroadcastChannel',ticket:session.ticket});const url=new URL(session.cable_path,location.href);url.protocol=location.protocol==='https:'?'wss:':'ws:';transportPhase='opening';ws=new WebSocket(url,['actioncable-v1-json','actioncable-unsupported']);
   connectTimer=setTimeout(()=>fail('Broadcast timed out during '+transportPhase+'. Check the browser WebSocket console and server log.'),20000);
   ws.addEventListener('open',()=>{transportPhase='socket open';status.textContent='Socket open. Waiting for server welcome…';});
   ws.addEventListener('message',event=>{try{const packet=JSON.parse(event.data);if(packet.type==='welcome'){transportPhase='welcomed';return ws.send(JSON.stringify({command:'subscribe',identifier}));}if(packet.type==='disconnect')return fail('Server closed the connection: '+String(packet.reason||'unknown reason')+'.');if(packet.type==='reject_subscription')return fail('Broadcast subscription was rejected. Reload and start a new session.');if(packet.type==='confirm_subscription'){transportPhase='subscribed';return send('start');}if(!packet.message)return;const data=packet.message;
    if(data.event==='ready')startRecorder();
    else if(data.event==='ack'){if(pending?.sequence!==data.sequence)return fail('Capture acknowledgement changed. Start a new session.');pending=null;pump();}
    else if(data.event==='sending'){badge.textContent=destination==='test'?'Private recording':'Sending to TikTok';badge.dataset.active='true';status.textContent=destination==='test'?'Recording on the server. Stop to download and review.':'Sending to TikTok. Confirm your broadcast in TikTok.';}
    else if(data.event==='ended'){finish('Session ended.');if(data.download_url){q('[data-download]').href=data.download_url;q('[data-download]').hidden=false;}}
    else if(data.event==='failed')fail(data.error||'The server encoder stopped.');
   }catch(e){fail('Broadcast response could not be processed. Start a new session.');}});
   ws.addEventListener('close',event=>{if(active)fail('Broadcast connection closed during '+transportPhase+' (code '+event.code+').'+(event.code===1006?' The browser did not receive a normal close; check its WebSocket console error.':' Start a new session.'));});ws.addEventListener('error',()=>{if(active){message('WebSocket transport error during '+transportPhase+'. Waiting for the close code…');status.textContent='Connection interrupted.';}});
  }catch(e){fail(e.message);}
 }
 function stop(){if(!active||stopping)return;stopping=true;controls();status.textContent='Stopping capture…';if(recorder?.state==='recording')recorder.stop();else{try{send('stop');}catch{finish('Session stopped.');}}}
 function release(){if(active)return message('Stop the session before releasing capture.');captureGeneration++;disableCamera();screen?.getTracks().forEach(t=>t.stop());mic?.getTracks().forEach(t=>t.stop());program?.getTracks().forEach(t=>t.stop());silent?.stop();audio?.close();clearInterval(paintTimer);screen=mic=program=audio=gain=analyser=null;muted=true;hold(false);preview.srcObject=null;source.srcObject=null;q('[data-placeholder]').hidden=false;sourceStatus();q('[data-meter]').value=0;status.textContent='Capture released.';}
 q('[data-share]').addEventListener('click',share);q('[data-camera]').addEventListener('click',()=>live(camera)?disableCamera():enableCamera());q('[data-camera-device]').addEventListener('change',()=>{if(live(camera))enableCamera();});q('[data-layout]').addEventListener('change',()=>{if(active&&missingSource())hold(true);});q('[data-mic]').addEventListener('click',toggleMic);q('[data-hold]').addEventListener('click',()=>{if(holding&&missingSource())return message(missingSource());hold(!holding);});q('[data-release]').addEventListener('click',release);q('[data-start]').addEventListener('click',start);q('[data-stop]').addEventListener('click',stop);
 q('[data-destination]').addEventListener('change',()=>{q('[data-start]').textContent=q('[data-destination]').value==='test'?'Start private test':'Start TikTok broadcast';});
 const unload=event=>{if(active){event.preventDefault();event.returnValue='';}};window.addEventListener('beforeunload',unload);
 const cleanup=()=>{finish('Session ended.');release();window.removeEventListener('beforeunload',unload);delete root.dataset.wired;};
 document.addEventListener('turbo:before-cache',cleanup,{once:true});window.addEventListener('pagehide',cleanup,{once:true});
 root.dataset.encoder=q('[data-start]').disabled?'missing':'ready';controls();if(!supported)message('Screen capture needs a compatible Firefox or Chrome browser over HTTPS. Your Mac does not need TikTok LIVE Studio.');
}
document.addEventListener('turbo:load',boot);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
