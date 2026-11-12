// Native Studio workflow with real scripts; billing/render/publication endpoints are fixtures.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'../..'),out=process.env.STUDIO_DELIVERY_PREVIEW_DIR||path.join(root,'tmp/studio-delivery');fs.mkdirSync(out,{recursive:true});
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.STUDIO_CHROMIUM_EXECUTABLE?{executablePath:process.env.STUDIO_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox','--no-zygote','--single-process']});try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[],requests=[];page.on('pageerror',e=>errors.push(e.message));
 const scene={id:1,name:'Product launch',objects:[],lock_version:0,settings:{timeline:{output:'video',width:1920,height:1080,fps:30,clips:[]}}};
 const project={id:1,name:'Business campaign',scenes:[scene],unassigned_scenes:[scene],productions:[]};
 const asset={id:7,name:'Product photograph',kind:'image',status:'ready',metadata:{},proxy_url:'/assets/photo.svg'};
 const scripts=['nevaeh-client','studio-dashboard','studio-app','studio-native','studio-authoring','studio-media','studio-create','studio-performance','studio-visual','vendor/tone/Tone-15.1.22','vendor/tone/Midi-2.0.28','studio-music-core','studio-music-audio','studio-music','studio-production','studio-edit-workbench','studio-ai','studio-delivery'];
 const html=`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">${['studio-visual','studio-authoring','studio-music','studio-dashboard','studio-edit-workbench','studio-delivery'].map(n=>`<link rel="stylesheet" href="/lightek/${n}.css">`).join('')}<main id="lightek-studio-dashboard" class="media-studio-focus" data-site-id="2" data-user-id="42" data-scene-id="1" data-workspace="edit" data-pwa-url="https://client.example/lightek/index.html" data-csrf-token="csrf"><div id="studio-root"></div></main>${scripts.map(n=>`<script defer src="/lightek/${n}.js"></script>`).join('')}`;
 let failQuote=true,published=false,invalidCheckout=true;
 const complete={id:13,type:'edit_media',scene_id:1,status:'completed',draft_preview:false,output:{output:'video',width:1080,height:1920,fps:30},artifacts:[{id:99,kind:'video',filename:'campaign.mp4',url:'/master.mp4'}]};
 await page.route('https://checkout.stripe.com/**',route=>route.fulfill({body:'Checkout fixture'}));
 await page.route('http://localhost:18449/**',route=>{
  const u=new URL(route.request().url());if(u.pathname.endsWith('/execute')){const req=route.request().postDataJSON();requests.push(req);let result={};
   if(req.capability.endsWith('bootstrap'))result={projects:[project]};
   else if(req.capability.endsWith('project.create'))result={project_id:1,scene_id:1};
   else if(req.capability.endsWith('assets.list'))result={assets:[asset],media_presets:[]};
   else if(req.capability.endsWith('timeline.save')){scene.settings.timeline=req.payload.timeline;scene.lock_version++;result={timeline:req.payload.timeline,lock_version:scene.lock_version};}
   else if(req.capability.endsWith('timeline.quote')){if(failQuote){failQuote=false;return route.fulfill({status:422,json:{error:'Pricing unavailable. Try again.'}});}result={operation_id:21,operation_type:'edit_media',status:'awaiting_payment',quote:{currency:'USD',total_cents:125}};}
   else if(req.capability.endsWith('render.quote')){assert.equal(req.payload.output,'movie');result={operation_id:22,operation_type:'build_scene',status:'awaiting_payment',quote:{currency:'USD',total_cents:225}};}
   else if(req.capability.endsWith('operations.list'))result={operations:[complete,{...complete,id:14,scene_id:8,artifacts:[{id:100,filename:'other-sequence.mp4'}]},{id:15,scene_id:1,type:'edit_media',status:'awaiting_payment',quote:{total_cents:100},artifacts:[]}],publications:published?[{id:31,status:'published',post_id:55}]:[]};
   else if(req.capability.endsWith('artifact.publish')){published=true;result={publication_id:31,status:'scheduled'};}
   else if(req.capability.endsWith('render.checkout'))result={checkout_url:invalidCheckout?'https://untrusted.example/checkout':'https://checkout.stripe.com/test'};
   return route.fulfill({json:{status:'completed',result}});
  }
  if(u.pathname.startsWith('/lightek/'))return route.fulfill({body:fs.readFileSync(path.join(root,'public',u.pathname)),contentType:u.pathname.endsWith('.css')?'text/css':'application/javascript'});
  if(u.pathname==='/assets/photo.svg')return route.fulfill({body:'<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="#dea952"/></svg>',contentType:'image/svg+xml'});
  return route.fulfill({body:html,contentType:'text/html'});
 });
 await page.goto('http://localhost:18449/dashboard/studio-broadcasting/workspace/1?site_id=2#/studio/1/edit');await page.locator('.ew-asset').waitFor();
 await page.evaluate(()=>{location.hash='#/studio';});await page.locator('[aria-label="Production format"]').selectOption('portrait');await page.getByRole('textbox',{name:'Project name'}).fill('Launch campaign');await page.locator('[data-vw-form=new] button').click();await page.locator('.ew-asset').waitFor();assert(requests.some(r=>r.capability.endsWith('project.create')&&r.payload.name==='Launch campaign'&&r.payload.format==='portrait'));
 await page.locator('.ew-asset').click();await page.locator('[data-ew=insert]').first().click();
 await page.locator('[data-ew=inspector][data-tab=titles]').click();await page.locator('[data-ew=title]').click();await page.locator('[data-title-field=text]').fill('New season. Same Lightek.');await page.locator('[data-title-field=text]').dispatchEvent('change');
 await page.locator('[data-production-mode=deliver]').click();await page.locator('[data-delivery=refresh]').waitFor();
 assert.equal(await page.getByText('Download other-sequence.mp4').count(),0,'completed masters stay with their sequence');
 await page.locator('[data-delivery-setting=format]').selectOption('portrait');let t=await page.evaluate(()=>LightekStudioTimeline.get());assert.equal(t.width,1080);assert.equal(t.height,1920);assert.equal(t.clips.length,1);assert.equal(t.titles[0].text,'New season. Same Lightek.');
 await page.locator('[data-delivery=quote-edit]').click();await page.getByText('Pricing unavailable. Try again.').waitFor();assert.equal(await page.locator('[data-delivery=quote-edit]').isEnabled(),true);
 await page.locator('[data-delivery=quote-edit]').click();await page.getByText('Edit export · quote #21').waitFor({timeout:5000}).catch(async e=>{console.log({requests:requests.slice(-5),errors,text:await page.locator('.studio-delivery').innerText()});throw e;});assert.equal(requests.filter(r=>r.capability.endsWith('render.quote')).length,0,'edit export never requests a Blender still');
 assert(requests.some(r=>r.capability.endsWith('timeline.save')&&r.payload.timeline.height===1920&&r.payload.timeline.titles[0].text==='New season. Same Lightek.'));
 await page.locator('.delivery-quote [data-delivery=checkout]').click();await page.getByText('Invalid checkout URL').waitFor();assert(page.url().startsWith('http://localhost:18449/'));
 await page.locator('[data-delivery-setting=format]').selectOption('square');assert.equal(await page.evaluate(()=>LightekStudioTimeline.dirty()),true,'edits after save remain unsaved');assert.equal(await page.evaluate(()=>studioSceneRecord(1).scene.settings.timeline.height),1920,'local edits do not mutate the saved baseline');await page.getByText('Your edit changed after this quote.',{exact:false}).waitFor();assert.equal(await page.locator('.delivery-quote [data-delivery=checkout]').count(),0);
 await page.locator('.delivery-advanced summary').click();await page.locator('[data-delivery=quote-shot]').click();await page.getByText('Blender shot · quote #22').waitFor();
 await page.locator('[data-a=studioArtifactPublish]').click();await page.locator('dialog [name=title]').fill('Campaign launch');await page.locator('dialog button[type=submit],dialog button:not([type])').first().click();await page.waitForFunction(()=>!document.querySelector('dialog'));assert.equal(requests.filter(r=>r.capability.endsWith('artifact.publish')).at(-1).payload.artifact_id,99);
 await page.getByText('Release #31').waitFor();assert.equal(await page.locator('.delivery-release a').getAttribute('href'),'https://client.example/lightek/index.html#/post/55');
 for(const width of [1440,1024,390]){await page.setViewportSize({width,height:1000});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'delivery fits '+width);await page.screenshot({path:path.join(out,'delivery-'+width+'.png'),fullPage:true});}
 invalidCheckout=false;await page.locator('[data-delivery=checkout][data-operation="15"]').click();await page.waitForURL('https://checkout.stripe.com/test');assert.deepEqual(errors,[]);
 console.log('STUDIO_DELIVERY_PASS edit→title→portrait→save→quote→recover→stale quote→Blender movie→publish→resume payment; desktop/tablet/phone');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
