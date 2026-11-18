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
    const uploadedFrame={...image,id:24,name:'Uploaded frame'};
    const sound={id:22,name:'Voice recording',kind:'audio',status:'ready',proxy_url:'/voice.wav',metadata:{duration:4.1}};
    const video={id:23,name:'Generated shot',kind:'video',status:'ready',metadata:{duration:5,width:540,height:960},proxy_url:'/video.mp4'};
    let generated=false,published=[],loads=0,recoverable=true,taught=false,frameImported=false,uploadAttempts=0;

    let cable, subscription, finishReply;
    let workerAvailability, draft;
    await page.routeWebSocket('ws://localhost:18447/cable',socket=>{
      cable=socket;
      socket.onMessage(message=>{
        const request=JSON.parse(message);
        subscription=request.identifier;
        socket.send(JSON.stringify({identifier:subscription,type:'confirm_subscription'}));
      });
    });

    await page.route(origin+'/**',async route=>{
      const url=new URL(route.request().url());
      if((url.pathname.startsWith('/lightek/')&&!url.pathname.endsWith('.html'))||url.pathname==='/lightek/nevaeh-reply-stream.js'){
        const file=path.join(root,'public',url.pathname);
        return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':'text/css'});
      }
      if(url.pathname.endsWith('/uploads')){
        assert.equal(route.request().method(),'POST');
        assert.match(route.request().postData(),/IMG_4512.HEIC/);
        if(++uploadAttempts===1)return route.fulfill({status:500,body:'Internal Server Error'});
        return route.fulfill({json:{signed_id:'signed-frame'}});
      }
      if(url.pathname.endsWith('/execute')){
        const request=route.request().postDataJSON();
        const key=request.capability.replace(/^studio\.(pwa\.|workspace\.)/,'');
        const data=request.payload;
        calls.push([key,data]);
        let result;
        switch(key){
          case 'nevaeh.conversation':
            if(data.text==='How do I use the timeline?'){
              assert.equal(data.stream,true);
              cable.send(JSON.stringify({identifier:subscription,message:{text:'You are in the timeline'}}));
              await new Promise(resolve=>{finishReply=resolve;});
            }
            if(data.retry_economy){result={text:'I’ve queued an Economy retry.',work_item_id:97};}
            else if(data.teach){taught=true;result={text:'Shortcut saved and ready to use.'};}
            else result={text:'You are in the '+data.view+' workspace.',status:'grounded'};
            break;
          case 'bootstrap': result={projects:[{id:3,name:'Production',unassigned_scenes:[scene]}]};break;
          case 'assets.list': result={assets:data.surface==='ai_input'?[image,...(frameImported?[uploadedFrame]:[])]:[image,sound,...(frameImported?[uploadedFrame]:[]),...(generated?[video]:[])]};break;
          case 'ai.status':
            if(workerAvailability==='error')return route.fulfill({status:503,json:{error:'Worker status request unavailable'}});
            if(workerAvailability==='standard'){
              result={connected:false,recipes:[],genesis_workers:[],render_pools:['standard'],performances:[]};
              break;
            }
            result={connected:true,device:{type:'cpu'},models:['sd-v1-5.safetensors'],genesis_workers:[{id:18,label:'Genesis worker',video:true,image:true}],render_pools:['local','remote'],performances:[{id:'musetalk',source:['image','video'],driver:'audio',configured:true}],recipes:['wan22_video','wan22_image_video','image'].map(id=>({id,ready:true,steps:20}))};break;
          case 'asset.import': frameImported=true;result={asset_id:24,status:'uploaded'};break;
          case 'ai.generate': generated=true;result={asset_id:23,status:'uploaded'};break;
          case 'ai.jobs': result=generated?[{...video,asset_id:23,preview_url:video.proxy_url}]:[];break;
          case 'operations.list':
            loads++;
            result={
              activity:data.activity_scene_id?[{id:81,label:'Generation',status:'ready',asset_id:23,teach:true},
                {id:83,label:'Generation',status:'failed',recovery:{action:'retry_economy',message:'Try Economy at up to 512 pixels.'}},
                ...(recoverable?[{id:79,label:'3D render',status:'recoverable',operation_id:46}]:[])]:[],
              operations:[{id:46,type:'build_scene',scene_id:7,status:recoverable?'failed':'pending',cpu_resumable:recoverable,error:recoverable?'private diagnostic':null,artifacts:[]},
                ...(draft?[{...draft,status:'completed',artifacts:[{id:75,kind:'video',filename:'Draft.mp4',url:'/draft.mp4'}]}]:[]),
                ...(data.activity_scene_id?[{id:71,type:'build_scene',scene_id:7,status:'completed',artifacts:[{id:77,kind:'video',filename:'Landscape render.mp4',url:'/video.mp4'}]}]:[])],
              publications:published
            };break;
          case 'blender.preview':
            assert.equal(data.scene_id,7);
            assert.deepEqual(data.procedural_script_params,{camera:'angle',lighting:'soft',motion:'spin'});
            assert.match(data.request_key,/-draft$/);
            if(!url.pathname.startsWith('/dashboard'))assert.equal(request.prefer_async,true);
            draft={id:70,scene_id:7,type:'build_scene',draft_preview:true,procedural_preview:true};
            result={operation_id:70,status:'pending'};break;
          case 'render.quote': result={operation_id:46,quote:{currency:'USD',total_cents:300}};break;
          case 'render.resume': recoverable=false;result={operation_id:46,status:'pending'};break;
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
          case 'timeline.quote': result={operation_id:56,status:'awaiting_payment',quote:{currency:'USD',total_cents:300}};break;
          default: throw Error('Unexpected capability '+key);
        }
        return route.fulfill({json:{status:'completed',result}});
      }
      if(url.pathname==='/draft.mp4'&&process.env.STUDIO_DRAFT_VIDEO){
        return route.fulfill({path:process.env.STUDIO_DRAFT_VIDEO,contentType:'video/mp4'});
      }
      if(url.pathname.endsWith('.mp4')||url.pathname.endsWith('.png'))return route.fulfill({status:204});
      const dashboard=url.pathname.startsWith('/dashboard');
      return route.fulfill({contentType:'text/html',body:`<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="/lightek/studio-unified.css">
        ${dashboard?'<div data-unified-studio data-site-id="2" data-scene-id="7" data-csrf-token="token" data-home="/dashboard/studio-broadcasting"></div>':'<div id="pwa"></div>'}
        <script src="/lightek/nevaeh-client.js"></script><script src="/lightek/nevaeh-reply-stream.js"></script><script src="/lightek/studio-unified.js"></script>
        ${dashboard?'':'<script>const host=document.querySelector("#pwa");function renderStudio(){if(location.hash.startsWith("#/studio"))LightekUnifiedStudio.pwa(host,location.hash.split("/")[2]);else {LightekUnifiedStudio.leave();host.textContent="PWA home";}}renderStudio();addEventListener("hashchange",renderStudio);</script>'}`});
    });
    const workspace=origin+'/dashboard/studio-broadcasting/workspace/7?site_id=2';
    await page.goto(workspace+'#/studio/7/create');
    await page.getByRole('button',{name:'5s AI Video Wan 2.2'}).waitFor();
    await page.getByLabel('Prompt').fill('Orbit the host desk');
    await page.getByText('Advanced',{exact:true}).click();
    await page.getByRole('spinbutton',{name:/Seed/}).fill('42');
    await page.getByLabel('Steps',{exact:true}).fill('21');
    const photo={name:'IMG_4512.HEIC',mimeType:'application/octet-stream',buffer:Buffer.from('test frame')};
    const startingFrameUpload=page.getByLabel('Upload starting frame (optional)',{exact:true});
    await startingFrameUpload.setInputFiles(photo);
    await page.getByRole('alert').getByText('Studio could not save this upload. Choose the file again to retry.').waitFor();
    await startingFrameUpload.setInputFiles(photo);
    await page.getByRole('button',{name:'Generate',exact:true}).click();
    assert(calls.some(([key,data])=>key==='asset.import'&&data.project_id===3&&data.signed_id==='signed-frame'));
    await page.getByRole('button',{name:'Add to timeline',exact:true}).click();
    await page.getByText('Edit saved.',{exact:true}).waitFor();
    const request=calls.find(([key])=>key==='ai.generate')[1];
    assert.deepEqual([request.recipe,request.seed,request.steps,request.input_asset_id,request.genesis_worker_id],['wan22_image_video',42,21,24,18]);
    assert.equal(scene.settings.timeline.clips[0].asset_id,23);
    assert.deepEqual([scene.settings.timeline.width,scene.settings.timeline.height],[640,360]);
    assert.match(request.request_key,/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/);

    await page.getByRole('button',{name:'AI Studio Create',exact:true}).click();
    await page.getByRole('button',{name:'Concept Art SD 1.5'}).click();
    await page.getByLabel('Prompt').fill('Artwork for the desk');
    await page.getByLabel('Aspect ratio').selectOption('9:16');
    await page.getByRole('button',{name:'Generate',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('.ls-controls button.ls-primary').disabled);
    assert(calls.some(([key,data])=>key==='ai.generate'&&data.aspect_ratio==='9:16'&&data.recipe==='image'&&data.genesis_worker_id===18));
    await page.getByRole('button',{name:'3D Procedural Movie'}).click();
    await page.getByRole('button',{name:'Render draft',exact:true}).click();
    await page.locator('video[src="/draft.mp4"]').waitFor();
    assert.equal(await page.getByRole('button',{name:'Prepare to publish'}).count(),0);
    await page.getByText('Full render',{exact:true}).click();
    await page.getByLabel('Render pool').selectOption('remote');
    await page.getByRole('button',{name:'Get render price'}).click();
    await page.getByRole('button',{name:'Resume Render from Checkpoint'}).waitFor();
    assert.equal(await page.getByText('private diagnostic').count(),0);
    await page.getByRole('button',{name:'Operation Details'}).click();
    await page.getByRole('dialog').getByText('private diagnostic').waitFor();
    await page.getByRole('button',{name:'Close',exact:true}).click();
    await page.getByRole('button',{name:'Resume Render from Checkpoint'}).click();
    assert(calls.some(([key,data])=>key==='render.quote'&&data.routing_mode==='remote'&&data.procedural_script_params.camera==='angle'));
    await page.getByRole('button',{name:'Character Performance & Lip-Sync'}).click();
    await page.getByLabel('Source face').selectOption('21');
    await page.getByLabel('Driver audio',{exact:true}).selectOption('22');
    await page.getByRole('button',{name:'Generate',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('.ls-controls button.ls-primary').disabled);
    assert(calls.some(([key,data])=>key==='ai.generate'&&data.recipe==='musetalk'&&data.input_asset_id===21&&data.driver_asset_id===22));
    await page.getByLabel('Engine',{exact:true}).selectOption('rhubarb');
    await page.getByLabel('Character rig',{exact:true}).selectOption('12');
    await page.getByLabel('Driver audio',{exact:true}).selectOption('22');
    await page.getByRole('button',{name:'Generate',exact:true}).click();
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
    await page.getByLabel('Source',{exact:true}).selectOption('portrait');
    await page.getByRole('button',{name:'Get export price'}).click();
    await page.getByRole('button',{name:'Continue to payment'}).waitFor();
    assert(calls.some(([key,data])=>key==='timeline.quote'&&data.source_asset_id===23));
    await page.setViewportSize({width:390,height:850});
    for(const name of ['AI Studio Create','Timeline & Edit','Media Library','Social & Publish']){
      await page.getByRole('button',{name,exact:true}).click();
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=390),name+' must fit on a phone');
    }
    assert(loads>0);
    recoverable=true;
    await page.goto(origin+'/lightek/index.html#/studio/7/timeline');
    await page.getByRole('heading',{name:'Timeline & Edit'}).waitFor();
    await page.getByRole('button',{name:/Generated shot/}).waitFor();
    await page.getByRole('button',{name:'Nevaeh',exact:true}).click();
    await page.getByLabel('Message Nevaeh').fill('How do I use the timeline?');
    await page.getByRole('button',{name:'Send',exact:true}).click();
    await page.getByText('You are in the timeline',{exact:true}).waitFor();
    assert.equal(await page.getByText('You are in the timeline workspace.').count(),0);
    finishReply();
    await page.getByText('You are in the timeline workspace.').waitFor();
    await page.getByRole('button',{name:'Media Library',exact:true}).click();
    await page.getByRole('button',{name:/Starting image/}).click();
    await page.getByLabel('Message Nevaeh').fill('How do I use this image?');
    await page.getByRole('button',{name:'Send',exact:true}).click();
    await page.getByText('You are in the library workspace.').waitFor();
    assert(calls.some(([key,data])=>key==='nevaeh.conversation'&&data.asset_id===21&&data.scene_id===7&&data.view==='library'));
    await page.getByRole('button',{name:'Activity',exact:true}).click();
    await page.getByText('Verified Result',{exact:true}).waitFor();
    await page.getByRole('button',{name:'Retry in Economy'}).click();
    await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(button=>button.textContent==='Retry in Economy'&&!button.disabled));
    assert(calls.some(([key,data])=>key==='nevaeh.conversation'&&data.retry_economy===83));
    await page.getByRole('button',{name:'Resume from Checkpoint',exact:true}).click();
    await page.getByRole('button',{name:'Resume from Checkpoint',exact:true}).waitFor({state:'hidden'});
    assert.equal(calls.filter(([key])=>key==='render.resume').length,2);
    await page.getByRole('button',{name:'Teach Nevaeh This Phrase'}).click();
    await page.getByLabel('New phrase').fill('Make my desk clip');
    await page.getByRole('button',{name:'Save shortcut'}).click();
    await page.getByText('Shortcut saved and ready to use.').waitFor();
    assert(taught);
    await page.getByRole('button',{name:'Close Nevaeh'}).click();
    await page.getByRole('button',{name:'Social & Publish',exact:true}).click();
    await page.getByRole('button',{name:'Landscape render.mp4'}).click();
    await page.getByRole('button',{name:/Approve crop/}).waitFor();
    assert(calls.some(([key,data])=>key==='timeline.quote'&&data.source_artifact_id===77&&data.social_prepare===true));
    await page.getByRole('button',{name:'Generated shot',exact:true}).click();
    await page.getByLabel('YouTube Shorts via Lightek').check();
    await page.getByLabel('YouTube audience').selectOption('false');
    await page.getByLabel('I own the distribution rights and authorize public publishing to Lightek and YouTube.').check();
    await page.getByLabel('I reviewed this clip and its destinations.').check();
    await page.getByRole('button',{name:'Submit to selected channels'}).click();
    await page.waitForFunction(()=>[...document.querySelectorAll('small')].some(el=>el.textContent.includes('YouTube ·')));
    assert(calls.some(([key,data])=>key==='asset.publish'&&data.youtube_consent&&data.youtube_made_for_kids===false));
    workerAvailability='error';
    await page.getByRole('button',{name:'AI Studio Create',exact:true}).click();
    await page.getByRole('alert').getByText('Studio couldn’t check worker availability.').waitFor();
    assert.equal(await page.getByRole('option',{name:'No available worker'}).count(),0);
    await page.getByRole('button',{name:'Try a 3D draft'}).click();
    await page.getByRole('button',{name:'Render draft',exact:true}).click();
    const draftPlayer=page.locator('video[src="/draft.mp4"]');
    await draftPlayer.waitFor();
    if(process.env.STUDIO_DRAFT_VIDEO){
      await page.waitForFunction(()=>document.querySelector('video[src="/draft.mp4"]')?.readyState>=1);
      assert.equal(await draftPlayer.evaluate(video=>video.duration),2);
    }
    assert.equal(await page.getByRole('button',{name:'Continue to payment'}).count(),0);
    await page.getByRole('button',{name:'5s AI Video Wan 2.2'}).click();
    workerAvailability='standard';
    await page.getByRole('button',{name:'Retry worker check'}).click();
    await page.getByRole('option',{name:'No available worker'}).waitFor({state:'attached'});
    await page.getByRole('button',{name:/3D Procedural Movie/}).click();
    await page.getByText('Full render',{exact:true}).click();
    await page.getByRole('option',{name:'Standard Studio Queue'}).waitFor({state:'attached'});
    await page.getByRole('button',{name:'Get render price'}).click();
    await page.getByRole('button',{name:'Continue to payment'}).waitFor();
    assert(calls.some(([key,data])=>key==='render.quote'&&data.routing_mode==='standard'));
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
