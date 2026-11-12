// Real browser layout and interaction checks using the native Dashboard modules and a scoped API fixture.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const repo=path.resolve(__dirname,'../..');
const artifacts=path.join(repo,'tmp/studio-dashboard-browser');fs.mkdirSync(artifacts,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.STUDIO_CHROMIUM_EXECUTABLE?{executablePath:process.env.STUDIO_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu']});
 try{
 const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
 const scene={id:1,name:'Episode one',settings:{},objects:[],lock_version:0},project={id:1,name:'Lightek Sessions',productions:[],unassigned_scenes:[scene],scenes:[scene]};
 const modules=['nevaeh-client','studio-dashboard','studio-app','studio-native','studio-authoring','studio-media','studio-create','studio-performance','studio-visual','vendor/tone/Tone-15.1.22','vendor/tone/Midi-2.0.28','studio-music-core','studio-music-audio','studio-music'];
 const html=`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;padding:16px;background:#080b12}*{box-sizing:border-box}</style>${['studio-visual','studio-authoring','studio-music','studio-dashboard'].map(n=>`<link rel="stylesheet" href="/lightek/${n}.css">`).join('')}<main id="lightek-studio-dashboard" data-site-id="2" data-user-id="42" data-scene-id="1" data-csrf-token="csrf"><div id="studio-root"></div></main>${modules.map(n=>`<script defer src="/lightek/${n}.js"></script>`).join('')}`;
 await page.route('http://localhost:18447/**',async route=>{
 const u=new URL(route.request().url());
 if(u.pathname.endsWith('/execute')){const req=route.request().postDataJSON();let result={};if(req.capability==='studio.pwa.bootstrap')result={projects:[project]};else if(req.capability.endsWith('assets.list'))result={assets:[],media_presets:[],creation_recipes:[]};else if(req.capability.endsWith('music.save')){scene.settings.music=req.payload.composition;scene.settings.music_revision=(scene.settings.music_revision||0)+1;scene.lock_version++;result={composition:scene.settings.music,revision:scene.settings.music_revision,lock_version:scene.lock_version};}return route.fulfill({json:{status:'completed',result}});}
 if(u.pathname.startsWith('/lightek/')){const f=path.join(repo,'public',u.pathname);return route.fulfill({body:fs.readFileSync(f),contentType:f.endsWith('.css')?'text/css':'application/javascript'});}
 return route.fulfill({body:html,contentType:'text/html'});
 });
 for(const width of [1440,1024,390]){
 await page.setViewportSize({width,height:1000});await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace/1?site_id=2#/studio/1/music');await page.locator('.music-workbench').waitFor();await page.locator('[data-music=starter]').click();
 await page.locator('.mw-track').filter({hasText:'Keys'}).click();await page.locator(`[data-music=write-note][data-pitch="${60+[1440,1024,390].indexOf(width)}"][data-step="0"]`).click();await page.locator('[data-music=save]').click();await page.waitForFunction(()=>document.querySelector('[data-music-status]').textContent.includes('saved'));
 const dimensions=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth,root:document.querySelector('#lightek-studio-dashboard').getBoundingClientRect().toJSON()}));console.log(width,JSON.stringify(dimensions));assert(dimensions.document<=width+1,'page overflow');assert.equal(await page.locator('iframe').count(),0);
 await page.screenshot({path:`${artifacts}/music-${width}.png`,fullPage:true});
 await page.locator('.mw-header a').first().click();await page.locator('.visual-workbench').waitFor();await page.screenshot({path:`${artifacts}/studio-${width}.png`,fullPage:true});
 }
 assert.deepEqual(errors,[]);console.log('STUDIO_BROWSER_PASS native Dashboard music/edit navigation, note creation and save at 1440/1024/390, no document overflow or JavaScript errors');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
