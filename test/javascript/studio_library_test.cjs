const assert=require('node:assert/strict');
const fs=require('node:fs');
const {chromium}=require('playwright');
const script=fs.readFileSync('public/lightek/studio-media.js','utf8');
const css=fs.readFileSync('public/lightek/index.html','utf8').match(/<style>([\s\S]*?)<\/style>/)?.[1]||'';
const communityCss=fs.readFileSync('public/lightek/community-app.css','utf8');
const fixture=`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}\n${communityCss}</style></head><body><main id="app"></main><script>
const app=document.getElementById('app'),A={},R={studio:()=>''},AF={studio:()=>{}},STUDIO_WORKSPACE_MODES=[],ST={loaded:true,busy:false,workspaceMode:'3d',projects:[{id:1,name:'Production one',productions:[{scenes:[{id:1,name:'Scene one',lock_version:0,settings:{},objects:[{id:1,name:'Phone body',object_type:'cube'}]}]}]},{id:2,name:'Production two',unassigned_scenes:[{id:2,name:'Scene two',lock_version:0,settings:{},objects:[{id:2,name:'Guest',object_type:'sphere'}]}]}]};
const E=value=>String(value).replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const me=()=>({id:1}),meProfile=()=>({id:1}),toast=message=>{window.lastToast=message};
const studioSceneRecords=()=>ST.projects.flatMap(project=>[...(project.productions||[]).flatMap(production=>production.scenes),...(project.unassigned_scenes||[])].map(scene=>({project,scene})));
const studioSceneRecord=id=>studioSceneRecords().find(record=>record.scene.id===Number(id));const studioCurrentSceneId=()=>Number(location.hash.split('/').at(-1))||1;
const studioWorkspaceSelectedObject=scene=>scene.objects[0];
window.LightekStudioApp={prepare:()=>{},story:()=>'',setQuote:()=>{}};
window.requests=[];
const builtins=[{key:'char_iris',name:'Iris',category:'characters',description:'Editable blocking mannequin.',target:'scene'},{key:'mat_worn_brass',name:'Worn Brass',category:'materials',description:'Apply a material.',target:'object'},{key:'audio_neural_pulse',name:'Neural Pulse Bed',category:'audio',description:'Generated audio.',target:'timeline'},{key:'gfx_lower_thirds',name:'Lower third',category:'graphics',description:'Generated graphic.',target:'timeline'}];
let assets=[{id:3,name:'Photo',kind:'image',status:'ready',url:'/asset/3',proxy_url:'/asset/3',metadata:{}},{id:2,name:'Model',kind:'glb',status:'ready',url:'/asset/2',proxy_url:'/asset/2',metadata:{}},{id:1,name:'Broken audio',kind:'audio',status:'failed',error:'Invalid media',url:'/asset/1',metadata:{}}];
const nevaeh={csrfHeaders:()=>({}),parseResponse:response=>response.json(),execute:async({capability,payload})=>{requests.push({capability,payload});
if(capability.endsWith('assets.list'))return {result:{assets:payload.before?[{id:0,name:'Older clip',kind:'video',status:'ready',url:'/asset/0',proxy_url:'/asset/0',metadata:{duration:2}}]:assets,builtins,next_before:payload.before?null:1}};
if(capability.endsWith('asset.retry')){assets=assets.map(asset=>asset.id===payload.asset_id?{...asset,status:'uploaded'}:asset);return {result:{status:'uploaded'}};}
if(capability.endsWith('asset.publish'))return {result:{publication_id:42,status:'draft'}};
const record=studioSceneRecord(payload.scene_id);if(record){record.scene.lock_version++;if(capability.endsWith('asset.use'))record.scene.settings.timeline={output:'video',width:1280,height:720,clips:[{asset_id:payload.asset_id,in:0,out:2,start:0,track:0,gain:1,keyframes:[]}]};}
return {result:{scene_id:payload.scene_id,lock_version:record?.scene.lock_version,object_ids:[12],asset_ids:capability.endsWith('library.apply')&&payload.key==='audio_neural_pulse'?[3]:[]}};
}};
function render(){const id=location.hash.split('/').at(-1);if(/^\\d+$/.test(id)){const record=studioSceneRecord(id);LightekStudioApp.prepare(record);app.innerHTML=LightekStudioApp.story(record,ST.workspaceMode)||'<h1>Saved scene</h1>';}else app.innerHTML=R.studio('library');}
A.studioLoad=async()=>render();
app.addEventListener('click',event=>{const button=event.target.closest('[data-a]');if(button&&A[button.dataset.a])A[button.dataset.a](button);});
window.addEventListener('hashchange',()=>render());
</script><script src="/studio-media.js"></script><script>location.hash='#/studio/library';render();AF.studio('library');</script></body></html>`;
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu']});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.route('https://library.test/**',route=>route.fulfill({contentType:route.request().url().endsWith('.js')?'application/javascript':'text/html',body:route.request().url().endsWith('.js')?script:fixture}));
  await page.goto('https://library.test/');await page.locator('[data-library-key="char_iris"]').waitFor();
  assert.equal(await page.locator('h1').textContent(),'Build with what you have.');
  await page.locator('[data-key="mat_worn_brass"] [data-library-scene]').selectOption('2');assert.equal(await page.locator('[data-key="mat_worn_brass"] [data-library-object] option').textContent(),'Guest');
  await page.locator('[data-key="mat_worn_brass"] button').click();await page.waitForFunction(()=>location.hash==='#/studio/2');
  let request=await page.evaluate(()=>requests.find(item=>item.capability.endsWith('library.apply')));assert.equal(request.payload.object_id,'2');assert.equal(request.payload.scene_id,2);assert.equal(request.payload.key,'mat_worn_brass');
  await page.evaluate(()=>{location.hash='#/studio/library';render();});
  const photo=page.locator('article').filter({has:page.locator('h3',{hasText:/^Photo$/})});await photo.locator('form button').first().click();await page.waitForFunction(()=>location.hash==='#/studio/1');
  assert(await page.locator('[data-timeline-preview]').isVisible());request=await page.evaluate(()=>requests.find(item=>item.capability.endsWith('asset.use')));assert.equal(request.payload.asset_id,3);assert.equal(request.payload.placement,'append');
  await page.evaluate(()=>{location.hash='#/studio/library';render();});
  await page.locator('button[data-a="studioAssetPublish"]').first().click();await page.locator('dialog input[name=title]').fill('Published photo');await page.locator('dialog form button').first().click();await page.waitForFunction(()=>lastToast==='Publication #42 queued');
  request=await page.evaluate(()=>requests.find(item=>item.capability.endsWith('asset.publish')));assert.equal(request.payload.title,'Published photo');assert.equal(request.payload.platform,'lightek_social');assert.match(request.payload.request_key,/^[a-f0-9-]{36}$/);
  await page.locator('[data-a="studioAssetRetry"]').click();await page.waitForFunction(()=>requests.some(item=>item.capability.endsWith('asset.retry')));
  await page.locator('[data-a="studioAssetsMore"]').click();await page.getByRole('heading',{name:'Older clip'}).waitFor();
  await page.locator('[data-media-form="filter"] input').fill('Brass');await page.locator('[data-media-form="filter"] button').click();assert.equal(await page.locator('[data-library-key]').count(),1);
  await page.locator('[data-media-form="filter"] input').fill('');await page.locator('[data-media-form="filter"] button').click();
  if(process.env.STUDIO_LIBRARY_SCREENSHOT)await page.screenshot({path:process.env.STUDIO_LIBRARY_SCREENSHOT});
  await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile overflow');assert.deepEqual(errors,[]);
  console.log('STUDIO_LIBRARY_UI_PASS recipe_target timeline_use publication retry pagination filter nested_projects mobile');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
