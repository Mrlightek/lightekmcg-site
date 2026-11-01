import {BlenderStream} from './rtc/BlenderStream.js';
export function mountRemotePanel(root,scene,compositor){
  const panel=document.createElement('section');panel.className='pwa-post';
  panel.innerHTML='<h3>Live Blender viewport</h3><p>Open this scene in a persistent Blender worker. Switch cameras, adjust the lens and scrub the timeline to see Blender restage the shot.</p><div class="pwa-post-actions"><button class="btn p sm" data-connect>Connect Blender</button><button class="btn sm" data-disconnect disabled>Disconnect</button></div><p role="status" data-status>Blender disconnected.</p><video data-video autoplay playsinline muted controls style="width:100%;max-height:65vh;background:#080d14" hidden></video><fieldset data-controls disabled><label>Camera <select data-camera></select></label><label> Lens · mm <input data-lens type="number" min="2" max="250" step="1" value="50"></label><button class="btn sm" data-save>Save lens to shot</button><label style="display:block">Blender frame <input data-frame type="range" min="0" max="249" value="0" step="1"><output data-position>1</output></label></fieldset><label><input data-composite type="checkbox"> Composite webcam with matched Blender depth · GPU viewport backend</label><output data-metrics style="display:block"></output>';
  root.querySelector('[data-spatial-canvas]').before(panel);
  const q=selector=>panel.querySelector(selector);let stream=null,credentials=null,disposed=false,busy=false,cameras=[];
  const api=async body=>{const response=await fetch('/api/lightek/pwa/studio/spatial',{method:'POST',credentials:'same-origin',headers:{...window.nevaeh.csrfHeaders(),'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await response.json();if(!response.ok)throw Error(result.error||'Blender session unavailable');return result;};
  const stop=async()=>{stream?.close();stream=null;compositor?.clearServerFrame();const previous=credentials;credentials=null;q('[data-controls]').disabled=true;q('[data-connect]').disabled=false;q('[data-disconnect]').disabled=true;q('[data-video]').hidden=true;
    if(previous)await api({operation:'close',session_id:previous.session_id}).catch(()=>{});
  };
  q('[data-connect]').onclick=async()=>{if(busy)return;busy=true;q('[data-connect]').disabled=true;q('[data-status]').textContent='Starting the Blender worker…';
    try{credentials=await api({scene_id:scene.id});if(disposed){await stop();return;}
      const video=q('[data-video]');video.hidden=false;
      stream=new BlenderStream(video,async()=>{credentials=await api({operation:'ticket',session_id:credentials.session_id});return credentials;},metrics=>{
        if(disposed)return;q('[data-status]').textContent=metrics.connection;
        q('[data-metrics]').textContent=[metrics.renderedFps!==undefined?`Blender ${metrics.renderedFps.toFixed(1)} fps`:null,metrics.renderMs!==undefined?`Render ${metrics.renderMs.toFixed(1)} ms`:null,metrics.decodedFps!==undefined?`Decoded ${metrics.decodedFps.toFixed(1)} fps`:null,metrics.pingRttMs!==undefined?`Ping RTT ${metrics.pingRttMs.toFixed(1)} ms`:null,metrics.frameRoundTripMs!==undefined?`Frame presentation round trip ${metrics.frameRoundTripMs.toFixed(1)} ms`:null].filter(Boolean).join(' · ');
      },message=>{
        if(message.type!=='SERVER_STATE'||disposed)return;
        cameras=message.payload.cameras;const select=q('[data-camera]'),selected=select.value;select.replaceChildren(...cameras.map(camera=>{const option=document.createElement('option');option.value=camera.id;option.textContent=camera.name;return option;}));select.value=cameras.some(c=>c.id===selected)?selected:cameras.find(c=>c.active)?.id||cameras[0]?.id||'';
        q('[data-controls]').disabled=!cameras.length;
        const source=cameras.find(camera=>camera.id===select.value);q('[data-lens]').disabled=source?.camera_type==='ORTHO';
        const savedCamera=source?.camera_type!=='ORTHO'&&scene.objects?.find(object=>String(object.id)===select.value);q('[data-save]').disabled=!savedCamera;q('[data-save]').title=savedCamera?'Save lens to this scene camera':'Add a saved camera in Layout to save lens changes';
        q('[data-frame]').max=String((scene.settings?.frame_end||250)-(scene.settings?.frame_start||1));
      },async(metadata,bitmap)=>{
        if(!bitmap)return;
        if(disposed||!q('[data-composite]').checked){bitmap.close();return;}
        try{const applied=await compositor?.updateServerFrame(metadata,bitmap);if(!applied)q('[data-status]').textContent='Color stream received. Matched GPU depth is not available from this backend.';}catch(error){q('[data-status]').textContent=error.message;}
      },()=>!disposed&&q('[data-composite]').checked);
      await stream.start();q('[data-disconnect]').disabled=false;
    }catch(error){await stop();q('[data-status]').textContent=error.message;}finally{busy=false;}
  };
  q('[data-composite]').onchange=()=>{if(!q('[data-composite]').checked)compositor?.clearServerFrame();};
  q('[data-disconnect]').onclick=()=>void stop().then(()=>{q('[data-status]').textContent='Blender disconnected.';});
  const camera=(commit=false)=>{const id=q('[data-camera]').value,lens=Number(q('[data-lens]').value);if(!id||!Number.isFinite(lens)||lens<2||lens>250)return;
    const payload={camera_id:id,mode:commit?'commit':'preview',role:'shot',matrix_order:'column-major',coordinate_space:'BLENDER_Z_UP_METERS',activate:true};if(cameras.find(camera=>camera.id===id)?.camera_type!=='ORTHO')payload.focal_length_mm=lens;
    stream?.socket.send('CAMERA_UPDATE',payload,'camera');};
  q('[data-camera]').onchange=()=>{q('[data-save]').disabled=!scene.objects?.some(object=>String(object.id)===q('[data-camera]').value);q('[data-lens]').value=String(cameras.find(c=>c.id===q('[data-camera]').value)?.focal_length_mm||50);camera();};
  q('[data-lens]').oninput=()=>camera();q('[data-save]').onclick=()=>camera(true);
  q('[data-frame]').oninput=()=>{const frame=Number(q('[data-frame]').value),start=Number(scene.settings?.frame_start||1);q('[data-position]').textContent=String(start+frame);
    stream?.socket.send('TIMELINE_SCRUB',{frame,blender_frame:start+frame,fps:{num:Number(scene.settings?.fps||24)*1000,den:Math.round(Number(scene.settings?.fps_base||1)*1000)},playback_state:'scrubbing',evaluate_keyframes:true},'timeline');};
  const visibility=()=>{if(document.visibilityState==='hidden')void stop();};document.addEventListener('visibilitychange',visibility);
  return {async refresh(){if(!stream||disposed)return;await stop();if(!disposed)await q('[data-connect]').onclick();},dispose(){disposed=true;document.removeEventListener('visibilitychange',visibility);void stop();panel.remove();}};
}
