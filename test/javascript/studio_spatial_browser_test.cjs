const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const {chromium}=require('playwright');
const fakeWorker=`self.onmessage=({data})=>{if(data.type==='init')self.postMessage({type:'ready'});if(data.type==='segment')self.postMessage({type:'segment-ready'});if(data.type==='frame'){const landmarks=Array.from({length:468},()=>({x:.5,y:.5,z:0}));const x=.5+Math.sin(data.time/1500)*.08;landmarks[33]={x:x-.08,y:.45,z:0};landmarks[263]={x:x+.08,y:.45,z:0};data.bitmap.close();self.postMessage({type:'result',landmarks,mask:data.segment?{width:2,height:2,bytes:new Uint8Array([0,255,0,255])}:null});}}`;
async function run({denied=false,noWebgl=false}={}){
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream',...(noWebgl?['--disable-webgl']:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])]});
 let scene={id:1,name:'Spatial production',lock_version:0,object_count:1,objects:[{id:1,name:'Blender cube',object_type:'cube',definition:{location:[0,0,1],rotation:[0,0,0],scale:[1,1,1],material:{color:[.8,.4,.1,1]}}}],settings:{}};
 const requests=[],errors=[];let uploads=0;
 try{
 const context=await browser.newContext({permissions:['camera'],viewport:{width:1440,height:1100},acceptDownloads:true}),page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('console',message=>{if(!noWebgl&&message.type()==='error'&&/THREE|Shader|GL_INVALID/.test(message.text()))errors.push(message.text());});
 await page.addInitScript(()=>{window.testStreams=[];const original=navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);navigator.mediaDevices.getUserMedia=async options=>{const stream=await original(options);window.testStreams.push(stream);return stream;};});
 if(denied)await page.addInitScript(()=>{navigator.mediaDevices.getUserMedia=()=>Promise.reject(new DOMException('Denied','NotAllowedError'));});
 await page.route('https://spatial.test/**',route=>{
  const url=new URL(route.request().url()),json=data=>route.fulfill({contentType:'application/json',body:JSON.stringify(data)});
  if(url.pathname==='/api/nevaeh/bootstrap')return json({identity:{id:1,profile:{id:1,name:'Spatial tester',profile_type:'creator'}},navigation:[],surfaces:[],capabilities:[]});
  if(url.pathname==='/api/lightek/pwa/uploads'){uploads++;assert(route.request().postDataBuffer().length>1000);return json({signed_id:'signed-recording'});}
  if(url.pathname==='/api/nevaeh/execute'){
   const request=route.request().postDataJSON();requests.push(request);const {capability,payload}=request;let result={};
   if(capability==='studio.pwa.bootstrap')result={projects:[{id:1,name:'Spatial project',productions:[],unassigned_scenes:[scene]}],object_types:['cube']};
   if(capability.endsWith('assets.list'))result={assets:[],builtins:[],camera_presets:[],blender_demos:[],media_presets:[]};
   if(capability.endsWith('scene.save')){scene.settings.workspace=payload.workspace;result={workspace:payload.workspace,lock_version:++scene.lock_version};}
   if(capability.endsWith('asset.import'))result={asset_id:42,status:'uploaded'};
   return json({status:'completed',result});
  }
  if(url.pathname==='/api/lightek/pwa/assets/9/proxy')return route.fulfill({contentType:'model/gltf-binary',body:fs.readFileSync(process.env.STUDIO_VIEWPORT_FIXTURE||'/tmp/native-viewport-proof.glb')});
  if(url.pathname.endsWith('/vision-worker.js'))return route.fulfill({contentType:'application/javascript',body:fakeWorker});
  const file=path.join('public',url.pathname);if(fs.existsSync(file)&&fs.statSync(file).isFile())return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'image/svg+xml'});
  return route.fulfill({status:404,body:''});
 });
 await page.goto('https://spatial.test/lightek/index.html#/studio/1');
 await page.locator('.studio-work-tabs [data-mode=spatial]').click();await page.locator('[data-spatial-root]').waitFor();
 if(noWebgl){await page.getByText(/Spatial \/ 4D requires WebGL/).waitFor();assert(await page.locator('[data-webcam-start]').isDisabled());assert.equal(uploads,0);assert.deepEqual(errors,[]);return;}
 await page.locator('[data-spatial-canvas] canvas').waitFor();assert.equal(uploads,0);
 const adapted=await page.evaluate(async()=>{
  const THREE=await import('/lightek/vendor/three/three.module.js'),{StudioSceneContent}=await import('/lightek/spatial/scene-content.js');
  const scene=new THREE.Scene(),content=new StudioSceneContent(scene);
  await content.load({objects:[{id:99,object_type:'imported_asset',definition:{native_source_preview:true,asset_proxy_url:'/api/lightek/pwa/assets/9/proxy'}},{id:10,object_type:'native_object',definition:{blender_object_name:'Cube',location:[2,3,4],rotation:[0,0,90],scale:[1,1,1],material_override:{color:[1,0,0,1],roughness:.2}}}]});
  let cube;content.group.traverse(node=>{if(node.name==='Cube')cube=node;});const result={location:cube.position.toArray(),rotation:cube.rotation.z,color:cube.material.color.toArray()};content.dispose();return result;
 });assert.deepEqual(adapted.location,[2,3,4]);assert(Math.abs(adapted.rotation-Math.PI/2)<1e-8);assert.deepEqual(adapted.color,[1,0,0]);
 await page.getByRole('button',{name:'Start webcam',exact:true}).click();
 if(denied){await page.getByText(/Webcam permission was denied/).waitFor();assert(await page.locator('[data-webcam-start]').isEnabled());assert.equal(uploads,0);return;}
 await page.getByText(/Webcam is on/).waitFor();await page.getByRole('button',{name:'Enable tracking',exact:true}).click();await page.getByText(/Tracking ready/).waitFor();
 await page.waitForTimeout(300);await page.getByRole('button',{name:'Calibrate head position',exact:true}).click();await page.getByText(/Calibrated\. Move your head/).waitFor();
 await page.waitForFunction(()=>!/X 0\.000/.test(document.querySelector('[data-spatial-readout]').textContent));
 await page.getByRole('button',{name:'Bring this Blender scene into the window',exact:true}).click();await page.getByText(/Blender scene geometry added/).waitFor();
 await page.locator('[data-spatial-files]').setInputFiles([{name:'blue.webm',mimeType:'video/webm',buffer:fs.readFileSync('/tmp/spatial-blue.webm')},{name:'red.webm',mimeType:'video/webm',buffer:fs.readFileSync('/tmp/spatial-red.webm')}]);
 await page.getByRole('button',{name:'View 3 · red.webm',exact:true}).waitFor();
 await page.getByRole('button',{name:'Play recorded angles',exact:true}).click();await page.getByText(/Playing synchronized/).waitFor();
 await page.getByRole('button',{name:'View 2 · blue.webm',exact:true}).click();await page.waitForTimeout(300);
 const blue=await page.locator('[data-spatial-canvas] canvas').screenshot();
 await page.getByRole('button',{name:'View 3 · red.webm',exact:true}).click();await page.waitForTimeout(400);
 const red=await page.locator('[data-spatial-canvas] canvas').screenshot({path:'/tmp/lightek-spatial-composition.png'});assert(!blue.equals(red),'switching angle changes the actual WebGL image');
 await page.locator('[name=view]').selectOption('orbit');await page.locator('[name=layout]').selectOption('array');
 await page.getByText('Window calibration & person layers',{exact:true}).click();await page.locator('[name=cutout]').check();await page.getByText(/Person cutout ready/).waitFor();
 await page.locator('[name=width]').fill('0.55');await page.locator('[name=width]').dispatchEvent('change');
 await page.getByRole('button',{name:'Save workspace',exact:true}).click();await page.getByText('Saved to your account',{exact:true}).waitFor();
 assert.equal(scene.settings.workspace.story.spatial.width,.55);assert.equal(scene.settings.workspace.story.spatial.layout,'array');assert.equal(uploads,0);
 // Workspace saving keeps capture running; recorded content includes the composed video textures.
 await page.getByRole('button',{name:'Record composition · video only',exact:true}).click();await page.getByText(/Recording the composed view/).waitFor();
 await page.waitForTimeout(1400);await page.getByRole('button',{name:'Stop recording',exact:true}).click();await page.locator('[data-spatial-download]:visible').waitFor();
 const [download]=await Promise.all([page.waitForEvent('download'),page.locator('[data-spatial-download]').click()]);const recordingPath='/tmp/spatial-recording.'+(download.suggestedFilename().endsWith('.mp4')?'mp4':'webm');await download.saveAs(recordingPath);
 const info=JSON.parse(cp.execFileSync(process.env.LIGHTEK_FFPROBE||'ffprobe',['-v','error','-show_streams','-of','json',recordingPath],{encoding:'utf8'}));assert(info.streams.some(s=>s.codec_type==='video'&&s.width>100));
 await page.getByRole('button',{name:'Save recording to Lightek library',exact:true}).click();await page.getByText(/Saved composition #42/).waitFor();assert.equal(uploads,1);assert.equal(requests.filter(r=>r.capability.endsWith('asset.import')).length,1);assert(!requests.some(r=>r.capability.includes('artifact.publish')||r.capability.includes('checkout')));
 await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'spatial controls fit mobile');
 await page.locator('.studio-work-tabs [data-mode="3d"]').click();await page.locator('.studio-viewport-canvas canvas').waitFor();await page.waitForFunction(()=>window.testStreams.every(stream=>stream.getTracks().every(track=>track.readyState==='ended')));assert.deepEqual(errors,[]);
 console.log('STUDIO_SPATIAL_BROWSER_PASS shipped_pwa fake_webcam synthetic_tracking real_video_textures crossfade scene_geometry save_settings actual_recording_decode authenticated_library_import mobile cleanup');
 }finally{await browser.close();}
}
(async()=>{await run();await run({denied:true});await run({noWebgl:true});console.log('STUDIO_SPATIAL_FAILURES_PASS denied_camera no_webgl_no_capture');})().catch(error=>{console.error(error);process.exitCode=1;});
