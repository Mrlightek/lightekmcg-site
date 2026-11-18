const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const root = path.resolve(__dirname,'../..');
const origin = 'http://localhost:18447';

(async ()=>{
  const browser=await chromium.launch({
    headless:true,executablePath:process.env.STUDIO_CHROMIUM_EXECUTABLE,
    args:['--no-sandbox','--no-zygote','--single-process']
  });
  try {
    const page=await browser.newPage({viewport:{width:1280,height:900}});
    page.setDefaultTimeout(10000);
    await page.addInitScript(() => {
      Object.defineProperty(Crypto.prototype,'randomUUID',{value:undefined,configurable:true});
    });
    const errors=[],calls=[];
    page.on('pageerror',error=>errors.push(error.message));
    const scene={id:7,name:'Pilot',lock_version:1,settings:{timeline:{width:640,height:360}},
      objects:[{id:12,name:'Host',definition:{character_profile:{}}}]};
    const image={id:21,name:'Starting image',kind:'image',status:'ready',proxy_url:'/image.png'};
    const sound={id:22,name:'Voice recording',kind:'audio',status:'ready',metadata:{duration:4.1}};
    const video={id:23,name:'Generated shot',kind:'video',status:'ready',metadata:{duration:5},proxy_url:'/video.mp4'};
    let generated=false,published=[],loads=0;

    await page.route(origin+'/**',async route=>{
      const url=new URL(route.request().url());
      if(url.pathname.startsWith('/lightek/')&&!url.pathname.endsWith('.html')){
        const file=path.join(root,'public',url.pathname);
        return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':'text/css'});
      }
      if(url.pathname.endsWith('/execute')){
        const request=route.request().postDataJSON();
        const key=request.capability.replace(/^studio\.(pwa\.|workspace\.)/,'');
        const data=request.payload;
        calls.push([key,data]);
        let result;
        switch(key){
          case 'bootstrap': result={projects:[{id:3,name:'Production',unassigned_scenes:[scene]}]};break;
          case 'assets.list': result={assets:data.surface==='ai_input'?[image]:[image,sound,...(generated?[video]:[])]};break;
          case 'ai.status': result={connected:true,device:{type:'cpu'},models:['sd-v1-5.safetensors'],recipes:['wan22_video','wan22_image_video','image'].map(id=>({id,ready:true,steps:20}))};break;
          case 'ai.generate': generated=true;result={asset_id:23,status:'uploaded'};break;
          case 'ai.jobs': result=generated?[{...video,asset_id:23,preview_url:video.proxy_url}]:[];break;
          case 'operations.list': loads++;result={operations:[],publications:published};break;
          case 'timeline.save': scene.settings.timeline=data.timeline;scene.lock_version++;result={timeline:data.timeline,lock_version:scene.lock_version};break;
          case 'performance.analyze': result={id:35,status:'pending'};break;
          case 'performance.analysis': result={id:35,status:'completed'};break;
          case 'performance.save': scene.lock_version++;result={lock_version:scene.lock_version};break;
          case 'performance.preview': result=data.operation_id?{operation_id:36,status:'completed',url:'/preview.mp4'}:{operation_id:36,status:'pending'};break;
          case 'social.accounts': result={connections:[{id:44,provider:'instagram',label:'Lightek Instagram'},{id:45,provider:'tiktok',label:'Lightek TikTok'}],youtube_enabled:true,youtube_origin:origin};break;
          case 'social.options':result={options:{creator_username:'lightek',privacy_level_options:['SELF_ONLY'],comment_disabled:true,duet_disabled:true,stitch_disabled:true}};break;
          case 'asset.publish': {
            const id=100+published.length;
            published.push({id,platform:data.platform,status:data.platform==='lightek_social'?'published':'pending',youtube_preparation:data.youtube_preparation,post_id:data.youtube_preparation?52:null});
            result={publication_id:id,status:'queued'};break;
          }
          case 'timeline.quote': result={operation_id:56,quote:{currency:'USD',total_cents:300}};break;
          default: throw Error('Unexpected capability '+key);
        }
        return route.fulfill({json:{status:'completed',result}});
      }
      if(url.pathname.endsWith('.mp4')||url.pathname.endsWith('.png'))return route.fulfill({status:204});
      const dashboard=url.pathname.startsWith('/dashboard');
      return route.fulfill({contentType:'text/html',body:`<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="/lightek/studio-unified.css">
        ${dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-csrf-token="token" data-home="/dashboard/studio-broadcasting"></div>':'<div id="pwa"></div>'}
        <script src="/lightek/nevaeh-client.js"></script><script src="/lightek/studio-unified.js"></script>
        ${dashboard?'':'<script>const host=document.querySelector("#pwa");function renderStudio(){if(location.hash.startsWith("#/studio"))LightekUnifiedStudio.pwa(host,location.hash.split("/")[2]);else {LightekUnifiedStudio.leave();host.textContent="PWA home";}}renderStudio();addEventListener("hashchange",renderStudio);</script>'}`});
    });
    const workspace=origin+'/dashboard/studio-broadcasting/workspace/7?site_id=2';
    await page.goto(workspace);
    await page.getByRole('button',{name:'5s Video Wan 2.2'}).waitFor();
    await page.getByLabel('Describe your scene').fill('Orbit the host desk');
    await page.getByText('Engine & ComfyUI Parameters',{exact:true}).click();
    await page.getByLabel('Seed',{exact:true}).fill('42');
    await page.getByLabel('Steps',{exact:true}).fill('21');
    await page.getByLabel('Starting frame (optional)').selectOption('21');
    await page.getByRole('button',{name:'Generate 5s video',exact:true}).click();
    await page.getByRole('button',{name:'Add to timeline',exact:true}).click();
    await page.getByText('Edit saved.',{exact:true}).waitFor();
    const request=calls.find(([key])=>key==='ai.generate')[1];
    assert.deepEqual([request.recipe,request.seed,request.steps,request.input_asset_id],['wan22_image_video',42,21,21]);
    assert.equal(scene.settings.timeline.clips[0].asset_id,23);
    assert.deepEqual([scene.settings.timeline.width,scene.settings.timeline.height],[640,360]);
    assert.match(request.request_key,/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/);

    await page.getByRole('button',{name:'AI Studio Create',exact:true}).click();
    await page.getByRole('button',{name:'Concept Art SD 1.5'}).click();
    await page.getByLabel('Describe your scene').fill('Artwork for the desk');
    await page.getByRole('button',{name:'Generate concept art'}).click();
    await page.waitForFunction(()=>!document.querySelector('.ls-controls button.ls-primary').disabled);
    assert(calls.some(([key,data])=>key==='ai.generate'&&data.model==='sd-v1-5.safetensors'&&data.recipe==='image'));
    await page.getByRole('button',{name:'3D Actor Blender + Rhubarb Lip Sync'}).click();
    await page.getByLabel('Character',{exact:true}).selectOption('12');
    await page.getByLabel('Voice recording',{exact:true}).selectOption('22');
    await page.getByRole('button',{name:'Animate character'}).click();
    await page.locator('video[src="/preview.mp4"]').waitFor();
    assert(calls.some(([key,data])=>key==='performance.save'&&data.analysis_id===35&&data.lip_sync_mode==='phoneme'&&data.lock_version===2));

    await page.getByRole('button',{name:'Social & Publish',exact:true}).click();
    await page.getByLabel('Instagram Reels').selectOption('44');
    await page.getByLabel('TikTok',{exact:true}).selectOption('45');
    await page.getByLabel('Privacy').selectOption('SELF_ONLY');
    for(const title of ['Branded content','Promotes my own brand','Contains AI-generated content'])
      await page.getByLabel(title,{exact:true}).selectOption(title.startsWith('Contains')?'true':'false');
    await page.getByLabel('YouTube Shorts via Lightek').check();
    await page.getByLabel('Publish this clip to the public Lightek feed to prepare it for YouTube.').check();
    await page.getByLabel('Post caption & hashtags').fill('Studio test clip');
    // Editing the caption requires a new review of public-feed consent.
    await page.getByLabel('Publish this clip to the public Lightek feed to prepare it for YouTube.').check();
    await page.getByLabel('I reviewed this clip and its destinations.').check();
    await page.getByRole('button',{name:'Submit to selected channels'}).click();
    await page.getByRole('link',{name:'Review and submit to Lightek YouTube'}).waitFor();
    assert(calls.some(([key,data])=>key==='asset.publish'&&data.platform==='instagram'&&data.connection_id===44&&data.reviewed));
    assert(calls.some(([key,data])=>key==='asset.publish'&&data.platform==='tiktok'&&data.tiktok_settings.privacy_level==='SELF_ONLY'&&data.tiktok_settings.disable_comment));
    assert(calls.some(([key,data])=>key==='asset.publish'&&data.platform==='lightek_social'&&data.youtube_preparation));

    await page.getByRole('button',{name:'Get export price'}).click();
    await page.getByRole('button',{name:'Continue to payment'}).waitFor();
    await page.setViewportSize({width:390,height:850});
    for(const name of ['AI Studio Create','Timeline & Edit','Media Library','Social & Publish']){
      await page.getByRole('button',{name,exact:true}).click();
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=390),name+' must fit on a phone');
    }
    assert(loads>0);
    await page.goto(origin+'/lightek/index.html#/studio/7/timeline');
    await page.getByRole('heading',{name:'Timeline & Edit'}).waitFor();
    await page.getByRole('button',{name:/Generated shot/}).waitFor();
    await page.getByRole('link',{name:'Exit Studio'}).click();
    await page.getByText('PWA home',{exact:true}).waitFor();
    assert.deepEqual(errors,[]);

    // Inject an unrecoverable render error and verify that PWA navigation survives.
    await page.evaluate(()=>Object.defineProperty(Crypto.prototype,'getRandomValues',{value:undefined,configurable:true}));
    await page.evaluate(()=>{location.hash='#/studio/7/timeline';});
    const recovery=page.getByRole('region',{name:'Lightek Studio recovery'});
    await recovery.getByRole('alert').waitFor();
    assert.match(await recovery.getByRole('link',{name:'Open advanced editor'}).getAttribute('href'),/workspace\/7\?advanced=1/);
    await recovery.getByRole('link',{name:'Exit Studio'}).click();
    await page.getByText('PWA home',{exact:true}).waitFor();
    console.log('UNIFIED_STUDIO_PASS legacy timeline, older browser startup, generation, saved edits, publishing requests, mobile layout and crash recovery');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
