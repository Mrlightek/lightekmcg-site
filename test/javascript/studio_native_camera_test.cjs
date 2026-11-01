const assert=require('node:assert/strict'),fs=require('node:fs');
const {chromium}=require('playwright');
const script=fs.readFileSync('public/lightek/studio-app.js','utf8');
const html=`<!doctype html><html><head><meta charset="utf-8"></head><body><main id="app"></main><script>
const app=document.getElementById('app'),A={},R={studio:()=>''},ST={loaded:true,busy:false,workspaceMode:'visual',projects:[]};
const E=value=>String(value??'').replace(/[&<>"]/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[char]));
const STUDIO_WAVE2_STATE={},STUDIO_V3_STATE={},STUDIO_W4_STATE={},STUDIO_WORKSPACE_LAYOUT={},STUDIO_W5_STATE={},STUDIO_WAVE2_TASKS=[];
const camera={id:5,name:'Native Camera',object_type:'camera',definition:{camera_type:'PERSP',lens:35,sensor_width:32,sensor_height:24,shift_x:0.2,blender_object_name:'Native Camera',dof_enabled:false}};
const record={project:{id:1,name:'Blender production'},scene:{id:1,name:'Native Stage',lock_version:0,settings:{render_engine:'CYCLES',active_camera:'Native Camera',resolution_x:1280,resolution_y:720,frame_start:1,frame_end:250,frame_current:1},objects:[camera]}};
const studioSceneRecord=()=>record,studioCurrentSceneId=()=>1,studioWorkspaceSelectedObject=()=>camera,meProfile=()=>({id:1});
window.requests=[];const toast=message=>window.lastToast=message;
const nevaeh={execute:async({capability,payload})=>{requests.push({capability,payload});if(capability.endsWith('render.quote'))return {result:{operation_id:10,quote:{total_cents:500}}};if(capability.endsWith('camera.save'))Object.assign(camera.definition,payload.properties);if(capability.endsWith('visual.save'))Object.assign(record.scene.settings,payload.render_settings);record.scene.lock_version++;return {result:{scene_id:1,object_id:5,lock_version:record.scene.lock_version}};}};
function render(){app.innerHTML=ST.workspaceMode==='publish'?LightekStudioApp.delivery(record,'publish'):LightekStudioApp.visual(record);}
A.studioLoad=async()=>render();app.addEventListener('click',event=>{const button=event.target.closest('[data-a]');if(button&&A[button.dataset.a])A[button.dataset.a](button);});
</script><script src="/studio-app.js"></script><script>LightekStudioApp.prepare(record);render();</script></body></html>`;
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu']});
 try{
  const page=await browser.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.route('https://camera.test/**',route=>route.fulfill({contentType:route.request().url().endsWith('.js')?'application/javascript':'text/html',body:route.request().url().endsWith('.js')?script:html}));await page.goto('https://camera.test/');
  const form=page.locator('[data-studio-form="camera"]');assert.equal(await form.locator('[name=lens]').inputValue(),'35');assert.equal(await form.locator('[name=sensor_width]').inputValue(),'32');assert.equal(await form.locator('[name=shift_x]').inputValue(),'0.2');
  assert.equal(await form.locator('[name=panorama_type] option').count(),6);
  await form.locator('[name=camera_type]').selectOption('PANO');await form.locator('[name=panorama_type]').selectOption('FISHEYE_EQUIDISTANT');await form.locator('[name=lens]').fill('85');await form.locator('[name=dof_enabled]').check();await form.locator('[name=focus_distance]').fill('3');await form.locator('[name=aperture_fstop]').fill('1.8');await form.locator('[name=aperture_blades]').fill('7');await form.locator('button[type=submit],button:not([type])').first().click();
  await page.waitForFunction(()=>lastToast==='Blender camera saved');let payload=await page.evaluate(()=>requests.find(item=>item.capability.endsWith('camera.save')).payload);assert.equal(payload.object_id,5);assert.equal(payload.properties.lens,'85');assert.equal(payload.properties.camera_type,'PANO');assert.equal(payload.properties.panorama_type,'FISHEYE_EQUIDISTANT');assert.equal(payload.properties.dof_enabled,true);assert.equal(payload.active,true);
  const visual=page.locator('[data-studio-form="visual"]');await visual.locator('[name=frame_end]').fill('30');await visual.locator('[name=frame_current]').fill('10');await visual.locator('[name=fps]').fill('30');await visual.locator('[name=samples]').fill('8');await visual.locator('button').click();await page.waitForFunction(()=>requests.some(item=>item.capability.endsWith('visual.save')));
  payload=await page.evaluate(()=>requests.find(item=>item.capability.endsWith('visual.save')).payload);assert.equal(payload.object_id,null);assert.equal(payload.render_settings.frame_current,10);assert.equal(payload.render_settings.fps,30);assert.equal(payload.render_settings.samples,8);
  await page.locator('[data-a="studioCameraRenderQuote"]').click();await page.waitForFunction(()=>ST.workspaceMode==='publish');assert.equal(await page.locator('[data-a="studioRenderCheckout"]').isVisible(),true);assert.equal(await page.evaluate(()=>requests.filter(item=>item.capability.endsWith('render.checkout')).length),0);assert.deepEqual(errors,[]);
  console.log('STUDIO_NATIVE_CAMERA_UI_PASS native_values six_panorama_modes dof_sensor_frame_controls save render_quote_no_charge');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
