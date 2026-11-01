import {mountGenerationPanel} from './generation-panel.js';
import {mountRemotePanel} from './remote-panel.js';
import {HeadPose,faceMeasurement} from './projection.js';
import {WebcamSource,VideoAngles} from './video-sources.js';
import {FaceTracker} from './tracker.js';
import {SpatialCompositor} from './compositor.js';
import {StudioSceneContent} from './scene-content.js';
import {SpatialRecording} from './output.js';

export function mountSpatial(root,{settings={},onSettings=()=>{},scene={},saveRecording}={}) {
  let remote={dispose(){}};
  let disposed=false,token=0,webcamItem=null,measurement=null,lastFace=0,lastMask=0,last=performance.now(),frame=0,lastReadout=0;
  const status=root.querySelector('[data-spatial-status]'),trackingStatus=root.querySelector('[data-tracking-status]');
  const say=message=>{status.textContent=message;};
  const control=name=>root.querySelector(`[name="${name}"]`);
  const config={view:'window',layout:'crossfade',depth:.08,mirror:true,cutout:false,distance:.6,width:.5,...settings};
  for(const key of ['view','layout','depth','mirror','cutout','distance','width']) {
    const element=control(key);if(!element)continue;
    if(element.type==='checkbox')element.checked=config[key];else element.value=config[key];
  }
  const pose=new HeadPose({distance:Number(config.distance),mirror:config.mirror});
  let compositor;
  try{compositor=new SpatialCompositor(root.querySelector('[data-spatial-canvas]'),{width:Number(config.width)});}
  catch(error){say('Spatial / 4D requires WebGL. This browser could not create a graphics context. The regular 3D Layout software preview remains available.');root.querySelectorAll('button,input,select').forEach(el=>el.disabled=true);return {dispose(){remote.dispose();}};}
  remote=mountRemotePanel(root,scene,compositor);
  const sceneContent=new StudioSceneContent(compositor.scene);
  const generation=mountGenerationPanel(root,scene,async result=>{
    if(disposed||!result.object)return;
    scene.lock_version=result.generation.scene_revision;
    scene.objects=[...(scene.objects||[]).filter(object=>object.id!==result.object.id),result.object];
    await sceneContent.load(scene);compositor.marker.visible=false;
    await remote.refresh?.();say('Generated asset is visible on stage and saved in Library.');
  });
  const recording=new SpatialRecording(compositor.renderer.domElement,{onStatus:say,onReady:output=>{
    const link=root.querySelector('[data-spatial-download]');link.href=output.url;link.download=output.filename;link.hidden=false;
    root.querySelector('[data-spatial-save-media]').disabled=false;
  }});
  root.querySelector('[data-spatial-scene]').onclick=async event=>{
    const button=event.target;button.disabled=true;
    try{const result=await sceneContent.load(scene);if(disposed)return;compositor.marker.visible=false;say(`Blender scene geometry added behind the video layers.${result.warnings?' Some viewport proxies could not load.':''}`);}
    catch(error){say(error.message);button.disabled=false;}
  };
  root.querySelector('[data-spatial-record]').onclick=()=>{
    try{if(recording.busy)return;root.querySelector('[data-spatial-download]').hidden=true;root.querySelector('[data-spatial-save-media]').disabled=true;recording.start();}catch(error){say(error.message);}
  };
  root.querySelector('[data-spatial-record-stop]').onclick=()=>recording.stop();
  root.querySelector('[data-spatial-save-media]').onclick=async event=>{
    const button=event.target;if(!recording.blob||!saveRecording)return;button.disabled=true;
    try{say('Uploading your recorded composition to Lightek…');const result=await saveRecording(recording.blob,recording.filename);if(disposed)return;
      say(`Saved composition #${result.asset_id} to your media library. Processing is queued; use it in a timeline, post or Live Studio when ready. WebM recordings can be exported to MP4 through the existing timeline workflow for OTT.`);
    }catch(error){if(!disposed)say(error.message);}finally{if(!disposed)button.disabled=false;}
  };
  const webcam=new WebcamSource(),angles=new VideoAngles(say);
  const tracker=new FaceTracker({onStatus:message=>{trackingStatus.textContent=message;},onResult:result=>{
    const video=webcamItem?.video;
    measurement=faceMeasurement(result.landmarks,video?video.videoWidth/video.videoHeight:4/3);
    if(measurement)lastFace=performance.now();
    if(result.mask){compositor.updateMask(result.mask);lastMask=performance.now();}
  }});
  const resetTracking=()=>{tracker.stop();measurement=null;lastFace=0;lastMask=0;pose.reference=null;trackingStatus.textContent='Tracking off.';};
  const updateList=()=>{
    const list=root.querySelector('[data-spatial-angles]');list.replaceChildren();
    angles.items.forEach((item,index)=>{
      const row=document.createElement('div');row.className='pwa-post-actions';
      const button=document.createElement('button');button.type='button';button.className='btn sm';button.textContent=`View ${index+1} · ${item.label}`;
      button.onclick=()=>{config.angle=index;list.querySelectorAll('button[data-angle]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));};
      button.dataset.angle=String(index);button.setAttribute('aria-pressed',String(index===(config.angle||0)));row.append(button);
      if(!item.live){
        const label=document.createElement('label');label.textContent='Start offset · s ';
        const input=document.createElement('input');input.type='number';input.step='.01';input.min='0';input.max=String(item.video.duration);input.value=String(item.offset);input.style.width='90px';input.setAttribute('aria-label',`${item.label} start offset`);
        input.onchange=()=>{const value=Number(input.value);if(!Number.isFinite(value)||value<0||value>=item.video.duration){input.value=String(item.offset);say('Offset must be within this video.');return;}item.offset=value;angles.seek(angles.clock);};label.append(input);row.append(label);
      }
      const remove=document.createElement('button');remove.type='button';remove.className='btn sm';remove.textContent=`Remove ${item.label}`;
      remove.onclick=()=>{if(item===webcamItem)stopWebcam();else{compositor.remove(item);angles.remove(item);config.angle=Math.min(config.angle||0,Math.max(0,angles.items.length-1));updateList();}};row.append(remove);list.append(row);
    });
  };
  const stopWebcam=()=>{
    token++;webcam.close();resetTracking();
    if(webcamItem){compositor.remove(webcamItem);angles.remove(webcamItem);webcamItem=null;}
    config.angle=0;updateList();say('Webcam stopped. Its camera tracks have been released.');
  };
  root.querySelector('[data-webcam-start]').onclick=async()=>{
    const button=root.querySelector('[data-webcam-start]');button.disabled=true;
    stopWebcam();const attempt=++token;
    try{
      say('Requesting webcam…');const stream=await webcam.open();
      if(disposed||attempt!==token){webcam.close();return;}
      const item=await angles.add({stream,label:'Webcam'});
      if(disposed||attempt!==token){angles.remove(item);return;}
      webcamItem=item;compositor.add(item);config.angle=angles.items.indexOf(item);updateList();
      stream.getVideoTracks()[0]?.addEventListener('ended',()=>{if(!disposed&&webcamItem===item)stopWebcam();},{once:true});
      say('Webcam is on. Enable tracking, face the camera, then Calibrate. No audio is captured.');
    }catch(error){if(!disposed&&attempt===token){webcam.close();say(error.name==='NotAllowedError'?'Webcam permission was denied. Allow camera access, then press Start webcam again.':error.message);}}
    finally{if(!disposed)button.disabled=false;}
  };
  root.querySelector('[data-webcam-stop]').onclick=stopWebcam;
  root.querySelector('[data-tracking-start]').onclick=()=>{
    if(!webcamItem){say('Start the webcam before enabling head tracking.');return;}
    tracker.start();
  };
  root.querySelector('[data-calibrate]').onclick=()=>{
    try{if(performance.now()-lastFace>500)throw new Error('No recent face position. Enable tracking and face the webcam.');pose.calibrate(measurement);say('Calibrated. Move your head left, right, up or closer to look through the window.');}
    catch(error){say(error.message);}
  };
  root.querySelector('[data-spatial-files]').onchange=async event=>{
    const input=event.target;input.disabled=true;
    try{
      for(const file of Array.from(input.files)){
        if(disposed)break;
        if(!file.type.startsWith('video/'))throw new Error('Choose video files supported by this browser.');
        if(file.size>500*1024*1024)throw new Error('Use video clips smaller than 500 MB.');
        say(`Loading ${file.name}…`);const item=await angles.add({file,label:file.name});
        if(disposed)break;compositor.add(item);
      }
      updateList();say('Angles loaded. Align start offsets, then Play. Switching views crossfades the video textures.');
    }catch(error){say(error.message);}finally{input.value='';input.disabled=false;}
  };
  root.querySelector('[data-spatial-play]').onclick=()=>angles.play().then(()=>say('Playing synchronized recorded angles. Webcam remains live.')).catch(error=>say(error.message));
  root.querySelector('[data-spatial-pause]').onclick=()=>{angles.pause();say('Recorded angles paused.');};
  const scrub=root.querySelector('[data-spatial-seek]');scrub.oninput=()=>angles.seek(Number(scrub.value));
  root.querySelector('[data-spatial-reset]').onclick=()=>{pose.reference=null;pose.eye={x:0,y:0,z:pose.distance};config.view='window';control('view').value='window';onSettings({...config,angle:undefined});say('Window centered. Calibrate to enable head parallax again.');};
  root.querySelectorAll('[data-spatial-setting]').forEach(element=>element.onchange=()=>{
    const key=element.name,value=element.type==='checkbox'?element.checked:element.type==='number'||element.type==='range'?Number(element.value):element.value;
    if(typeof value==='number'&&(!Number.isFinite(value)||value<Number(element.min)||value>Number(element.max))){element.value=config[key];return;}
    config[key]=value;pose.mirror=config.mirror;pose.distance=Number(config.distance);compositor.width=Number(config.width);
    if(key==='mirror'||key==='distance'){pose.reference=null;say('Calibration changed. Face the camera and Calibrate again.');}
    if(key==='cutout')tracker.enableSegmentation(value);
    onSettings({...config,angle:undefined});
  });
  const visibility=()=>{if(document.hidden){recording.stop();angles.pause();stopWebcam();}};
  document.addEventListener('visibilitychange',visibility);
  const animate=now=>{
    if(disposed)return;const dt=Math.min((now-last)/1000,.1);last=now;
    if(webcamItem){tracker.sample(webcamItem.video,now);if(config.cutout&&tracker.ready)tracker.enableSegmentation(true);}
    const fresh=now-lastFace<700;
    const target=fresh?pose.estimate(measurement,webcamItem?.video.videoWidth/webcamItem?.video.videoHeight):null;
    const eye=pose.smooth(target||{x:0,y:0,z:pose.distance},dt);
    compositor.render({...config,eye,angle:config.angle||0,maskFresh:now-lastMask<700},dt);angles.tick(now);
    if(document.activeElement!==scrub){scrub.max=String(angles.duration===0x7fffffff?0:angles.duration);scrub.value=String(angles.clock);}
    if(now-lastReadout>100){lastReadout=now;root.querySelector('[data-spatial-readout]').textContent=`Eye estimate: X ${eye.x.toFixed(3)} · Y ${eye.y.toFixed(3)} · Z ${eye.z.toFixed(3)} m${pose.reference&&!fresh?' · face lost; returning to center':''}`;}
    frame=requestAnimationFrame(animate);
  };
  frame=requestAnimationFrame(animate);
  return {dispose(){generation.dispose();remote.dispose();disposed=true;token++;cancelAnimationFrame(frame);document.removeEventListener('visibilitychange',visibility);webcam.close();tracker.stop();angles.dispose();recording.dispose();sceneContent.dispose();compositor.dispose();}};
}
