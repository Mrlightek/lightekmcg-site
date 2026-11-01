/* Classic-script bridge: render the workspace synchronously, load its ES modules on demand. */
(() => {
  STUDIO_WORKSPACE_MODES.splice(3,0,{key:'spatial',label:'Spatial / 4D',description:'Webcam compositing, a head-tracked window and synchronized video angles.'});
  const ui=window.LightekStudioApp,previous=ui.story;
  const number=(name,label,value,min,max,step)=>`<label class="fld"><span>${label}</span><input data-spatial-setting name="${name}" type="number" value="${value}" min="${min}" max="${max}" step="${step}" required></label>`;
  ui.story=(record,mode)=>{
    if(mode!=='spatial')return previous(record,mode);
    return `<section class="pwa-post" data-spatial-root data-scene="${Number(record.scene.id)}"><span class="eb">Lightek Studio · Spatial / 4D · First slice</span><h2>Look through the screen.</h2><p>Start your webcam → Enable tracking → face the camera → Calibrate → move your head. Foreground and background objects reveal the window parallax immediately.</p><div class="pwa-post-actions"><button class="btn p sm" data-webcam-start>Start webcam</button><button class="btn sm" data-webcam-stop>Stop webcam</button><button class="btn sm" data-tracking-start>Enable tracking</button><button class="btn sm" data-calibrate>Calibrate head position</button><button class="btn sm" data-spatial-reset>Center window</button><button class="btn sm" data-spatial-scene>Bring this Blender scene into the window</button></div><p role="status" data-spatial-status>Webcam off. Camera access begins only when you press Start webcam. No microphone, recording or upload.</p><p role="status" data-tracking-status>Tracking off. Models download from Google and jsDelivr when enabled; frames are processed locally.</p><div data-spatial-canvas style="width:100%;height:clamp(300px,55vh,650px);overflow:hidden;border-radius:12px;background:#101825"></div><output data-spatial-readout style="display:block;margin:8px 0;font-variant-numeric:tabular-nums"></output><div class="g3"><label class="fld"><span>Viewing mode</span><select data-spatial-setting name="view"><option value="window">Head-tracked window</option><option value="orbit">Orbit · drag / zoom</option></select></label><label class="fld"><span>Video arrangement</span><select data-spatial-setting name="layout"><option value="crossfade">Crossfade angles</option><option value="array">Spatial array · see all angles</option></select></label><label class="fld"><span>Video angles · up to four total</span><input data-spatial-files type="file" multiple accept="video/*"></label></div><div data-spatial-angles></div><div class="pwa-post-actions"><button class="btn sm" data-spatial-play>Play recorded angles</button><button class="btn sm" data-spatial-pause>Pause recorded angles</button><label class="fld"><span>Shared video time · seconds</span><input data-spatial-seek type="range" value="0" min="0" max="0" step="0.01"></label></div><details><summary>Window calibration & person layers</summary><div class="g3">${number('distance','Eye distance at calibration · meters',.6,.3,1.2,.01)}${number('width','Physical viewport width · meters',.5,.15,1.5,.01)}${number('depth','Person layer displacement · meters',.08,0,.2,.01)}</div><label><input data-spatial-setting type="checkbox" name="mirror" checked> Mirror webcam and head X direction</label><label style="display:block"><input data-spatial-setting type="checkbox" name="cutout"> Person cutout + layered 2.5D displacement · requires tracking</label><p>Distance is estimated from apparent eye spacing and can vary with head rotation. Enter the physical width of this viewport and your distance before calibrating. Segmentation separates person/background; it is not reconstructed volumetric depth.</p></details><p>Recorded angles use a shared clock, per-angle start offsets and drift correction. Webcam/remote live streams have independent capture delays. Crossfading is a view transition, not synthesis of unseen viewpoints.</p><h3>Make a shareable clip</h3><div class="pwa-post-actions"><button class="btn p sm" data-spatial-record>Record composition · video only</button><button class="btn sm" data-spatial-record-stop>Stop recording</button><a class="btn sm" data-spatial-download hidden>Download recording</a><button class="btn sm" data-spatial-save-media disabled>Save recording to Lightek library</button><a class="btn sm" href="#/studio/library">Publish / edit from Library</a><a class="btn sm" href="/dashboard/live">Live Studio</a></div><p>Recording bakes your head/camera movement, Blender geometry and video textures into ordinary video for sharing. This first browser recorder is silent; add sound in the existing media timeline. Recordings stop after 3 minutes or approximately 200 MB. Saving uploads only the recorded composition you select. Live Studio can use that library clip as its program source.</p><p>Save workspace stores calibration and display settings. Local video selections and live camera streams remain temporary. Leaving this workspace or hiding the tab releases the webcam. Interactive head tracking remains on Lightek; exported clips preserve the recorded camera movement. This does not reproduce Blender lighting, simulations or final-render quality in WebGL.</p></section>`;
  };
  let active=null,loading=null,generation=0;
  const reconcile=()=>{
    const root=document.querySelector('[data-spatial-root]');
    if(active?.root===root||(root&&loading===root)||(!root&&!active&&!loading))return;
    generation++;active?.experience.dispose();active=null;loading=null;
    if(!root)return;
    const attempt=generation;loading=root;
    import('./spatial/experience.js').then(({mountSpatial})=>{
      if(attempt!==generation||!root.isConnected)return;
      const sceneId=Number(root.dataset.scene);
      const scene=studioSceneRecord(sceneId)?.scene||{};
      const experience=mountSpatial(root,{scene,saveRecording:async(blob,filename)=>{
        const body=new FormData();body.append('file',blob,filename);body.append('purpose','studio_asset');
        const response=await fetch('/api/lightek/pwa/uploads',{method:'POST',credentials:'same-origin',headers:nevaeh.csrfHeaders(),body});
        const upload=await nevaeh.parseResponse(response);
        const result=await nevaeh.execute({capability:'studio.workspace.asset.import',payload:{signed_id:upload.signed_id,name:'Spatial composition · '+scene.name,request_key:crypto.randomUUID()}});
        return result.result;
      },settings:STUDIO_WAVE2_STATE.spatial||{},onSettings:settings=>{
        if(studioCurrentSceneId()!==sceneId)return;
        STUDIO_WAVE2_STATE.spatial=settings;
        const status=document.getElementById('studio-save-status');if(status)status.textContent='Unsaved spatial settings · Save workspace';
      }});
      active={root,experience};loading=null;
    }).catch(error=>{if(attempt===generation){root.querySelector('[data-spatial-status]').textContent=`Spatial workspace could not load: ${error.message}`;loading=root;}});
  };
  let queued=false;
  new MutationObserver(()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;reconcile();});}).observe(app,{childList:true,subtree:true});
  window.addEventListener('pagehide',()=>{generation++;active?.experience.dispose();active=null;loading=null;});
  reconcile();
})();
