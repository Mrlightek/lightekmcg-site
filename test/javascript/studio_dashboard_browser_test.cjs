// Real browser layout and interaction checks using the native Dashboard modules and a scoped API fixture.
const fs=require('fs'),path=require('path'),assert=require('assert/strict'),{chromium}=require('playwright');
const repo=path.resolve(__dirname,'../..');
const artifacts=path.join(repo,'tmp/studio-dashboard-browser');fs.mkdirSync(artifacts,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.STUDIO_CHROMIUM_EXECUTABLE?{executablePath:process.env.STUDIO_CHROMIUM_EXECUTABLE}:{}),args:['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{
 const page=await browser.newPage(),errors=[];let handoffRequests=0,firstCharacterSave;page.on('pageerror',e=>errors.push(e.message));
 let projectCreations=0,starterRequests=0,starterPolls=0,variantRequests=0,variantPolls=0,photoUploads=0,photoBuilds=0,editUploads=0,rigUploads=0,editAssetReads=0,editSaves=0;
 const scene={id:1,name:'Episode one',settings:{},objects:[{id:10,name:'Hero',object_type:'cube',definition:{location:[0,0,1],scale:[1,1,2],material:{color:'#c9a35d'}}}],lock_version:0},second={id:2,name:'Scene two',settings:{},objects:[],lock_version:0},project={id:1,name:'Lightek Sessions',productions:[],unassigned_scenes:[scene,second],scenes:[scene,second]};
 const proofDir=process.env.STUDIO_CHARACTER_PROOF;
 const characterInventory=proofDir?JSON.parse(fs.readFileSync(path.join(proofDir,'asset.json'))).scenes[0]:null;
 const previewId=100;
 const previewObject={id:3900,name:'Detective Avery · Blender source',object_type:'imported_asset',
   definition:{asset_id:previewId,native_source_preview:true,asset_proxy_url:'/api/lightek/pwa/assets/100/proxy'}};
 const stageObjects=characterInventory?[
   previewObject,
   ...characterInventory.cameras.map((item,index)=>({...item,id:4000+index,object_type:'camera'})),
   ...characterInventory.objects.map((item,index)=>({...item,id:4200+index,object_type:'native_object'}))
]:[previewObject,{id:3901,name:'Face fixture',object_type:'native_object',
   definition:{native_type:'MESH',shape_keys:[{name:'Smile',value:0}]}}];
 const characterScene={id:4,name:'Detective Avery',settings:{...characterInventory?.settings,active_camera:characterInventory?.active_camera,
   rigged_character:true,studio_entry:'stage',native_blender_asset_id:previewId},objects:stageObjects,lock_version:0};
 const modules=['nevaeh-client','studio-dashboard','studio-app','studio-native','studio-authoring','studio-media','studio-create','studio-performance','studio-visual','vendor/tone/Tone-15.1.22','vendor/tone/Midi-2.0.28','studio-music-core','studio-music-audio','studio-music','studio-production','studio-edit-workbench','studio-ai','studio-delivery'];
 const html=`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;padding:16px;background:#080b12}*{box-sizing:border-box}</style>${['studio-visual','studio-authoring','studio-music','studio-dashboard','studio-edit-workbench','studio-ai','studio-delivery'].map(n=>`<link rel="stylesheet" href="/lightek/${n}.css">`).join('')}<main id="lightek-studio-dashboard" class="media-studio-focus" data-site-id="2" data-user-id="42" data-scene-id="1" data-csrf-token="csrf"><div id="studio-root"></div></main>${modules.map(n=>`<script defer src="/lightek/${n}.js"></script>`).join('')}<script type="importmap">{"imports":{"three":"/lightek/vendor/three/three.module.js"}}</script><script type="module" src="/lightek/studio-viewport.js"></script>`;
 await page.route('http://localhost:18447/**',async route=>{
 const u=new URL(route.request().url());
 if(u.pathname.endsWith('/uploads')){
   assert.match(route.request().headers()['content-type'],/multipart\/form-data/);
   if(route.request().postData().includes('guest-rig.blend')){
     rigUploads++;
     return route.fulfill({json:{signed_id:'rig-upload-token'}});
   }
   if(route.request().postData().includes('opening-photo.png')){
     editUploads++;
     return route.fulfill({json:{signed_id:'edit-upload-token'}});
   }
   assert.match(route.request().postData(),/portrait.png/);
   photoUploads++;
   return route.fulfill({json:{signed_id:'portrait-test-token'}});
 }
 if(u.pathname.endsWith('/execute')){const req=route.request().postDataJSON();let result={};if(req.capability.endsWith('cast.create')){
   assert.equal(req.payload.photo_signed_id,'portrait-test-token');assert.equal(req.payload.name,'Photo lead');
   photoBuilds++;result={asset_id:41,status:'processing'};
 }else if(req.capability.endsWith('starter.scene.create')){if(req.payload.character){
    variantRequests++;
    assert.equal(req.payload.name,'Detective Avery');
    assert.deepEqual(req.payload.character,{rig:'ellie_v2',height:1.15,facing:30,tint:'#b08050',pose:'waving'});
    if(!firstCharacterSave){
      firstCharacterSave=req.payload.request_key;
      return route.fulfill({status:503,json:{error:'The character worker is temporarily unavailable.'}});
    }
    assert.equal(req.payload.request_key,firstCharacterSave,'retry uses the original request key');
    result={asset_id:100,name:'Detective Avery',variant:true,status:'uploaded',phase:'queued'};
   }else{
     starterRequests++;assert.equal(req.payload.name,'Rain and Snow');result={asset_id:99,name:'Rain and Snow',status:'uploaded',phase:'queued'};
   }}else if(req.capability.endsWith('starter.scene.status')){result=variantRequests>1?{asset_id:100,name:'Detective Avery',variant:true,status:++variantPolls>1?'ready':'processing',phase:variantPolls>1?'ready':'building_scene',scene_id:4,project_id:3}:starterRequests?{asset_id:99,name:'Rain and Snow',status:++starterPolls>1?'ready':'processing',phase:starterPolls>1?'ready':'importing_rain_v3',scene_id:3,project_id:2}:null;}else if(req.capability.endsWith('project.create')){projectCreations++;if(req.payload.studio_entry==='stage')scene.settings.studio_entry='stage';result={project_id:1,scene_id:1};}else if(req.capability==='studio.pwa.bootstrap')result={projects:[project,...(starterPolls>1?[{id:2,name:'Rain and Snow',productions:[],unassigned_scenes:[{id:3,name:'Rain and Snow',settings:{},objects:[],lock_version:0}]}]:[]),...(variantPolls>1?[{id:3,name:'Detective Avery',productions:[],unassigned_scenes:[characterScene]}]:[])]};else if(req.capability.endsWith('ai.status'))result={connected:true,device:{type:'cuda',vram_total:24*1073741824,vram_free:18*1073741824},recipes:[{id:'wan22_video',name:'Wan 2.2',kind:'video',steps:20,ready:true}],performances:[{id:'musetalk',name:'MuseTalk',action:'Lip sync a performance',configured:false}]};else if(req.capability.endsWith('ai.jobs'))result=[{asset_id:12,status:'ready',kind:'video',name:'Latest shot',prompt:'Portrait close-up',seed:42,steps:20,preview_url:'/shot.mp4'}];else if(req.capability.endsWith('ai.setup.status'))result={can_manage:false};else if(req.capability.endsWith('asset.import')){
   if(req.payload.signed_id==='rig-upload-token')result={asset_id:172,status:'uploaded'};
   else{
     assert.equal(req.payload.signed_id,'edit-upload-token');
     editAssetReads=0;
     result={asset_id:171,status:'uploaded'};
   }
 }else if(req.capability.endsWith('look.status')&&req.payload.scene_id===4){
   result={lock_version:0,targets:[{object_id:3901,target:'',slot:0,name:'Face fixture / Skin',fields:['color'],values:{color:[.2,.3,.4,1]}}]};
 }else if(req.capability.endsWith('material.save')&&req.payload.scene_id===4){
   assert.equal(req.payload.object_id,3901);
   assert.equal(req.payload.lock_version,0);
   assert.deepEqual(req.payload.values.color,[1,0,0,1]);
   result={lock_version:1};
 }else if(req.capability.endsWith('blender.authoring.edit')&&req.payload.scene_id===4){
   assert.equal(req.payload.object_id,3901);
   assert.equal(req.payload.lock_version,1);
   assert.deepEqual(req.payload.command,{kind:'shape_key',name:'Smile',value:.5});
   result={lock_version:2};
 }else if(req.capability.endsWith('performance.preview')&&req.payload.scene_id===4){
   assert.equal(req.payload.scene_playback,true);
   result={status:'completed',url:'/character-preview.mp4'};
 }else if(req.capability.endsWith('blender.preview')&&req.payload.scene_id===4){
   result={status:'completed',url:'/preview.png'};
 }else if(req.capability.endsWith('assets.list')){
   const editPhoto={id:171,name:'opening-photo.png',kind:'image',status:++editAssetReads>1?'ready':'uploaded',proxy_url:'/preview.png',metadata:{width:1,height:1}};
   result={assets:[{id:7,name:'Opening shot',kind:'video',status:'ready',metadata:{duration:2}},...(editUploads?[editPhoto]:[]),...(rigUploads?[{id:172,name:'guest-rig.blend',kind:'blend',status:'ready',native_url:'/rig.blend',metadata:{scenes:[{objects:[{definition:{native_type:'ARMATURE'}}]}]}}]:[])],media_presets:[],creation_recipes:[]};
 }else if(req.capability.endsWith('operations.list'))result={operations:[{id:20,type:'build_scene',status:'completed',draft_preview:false,artifacts:[{id:30,kind:'video',filename:'Finished shot.mp4',url:'/shot'}]},{id:21,type:'build_scene',status:'completed',draft_preview:true,artifacts:[{id:31,kind:'video',filename:'Draft.mp4',url:'/draft'}]}],publications:[]};else if(req.capability.endsWith('artifact.use')){assert.equal(req.payload.scene_id,1);assert.equal(req.payload.artifact_id,30);handoffRequests++;if(handoffRequests%2===1)result={status:'uploaded',asset_id:7};else{scene.lock_version++;scene.settings.timeline={output:'video',width:1280,height:720,clips:[{asset_id:7,in:0,out:2,start:0,track:0}]};result={status:'ready',asset_id:7,lock_version:scene.lock_version,timeline:scene.settings.timeline};}}else if(req.capability.endsWith('timeline.save')){if(req.payload.timeline.clips.some(clip=>clip.asset_id===171))editSaves++;scene.settings.timeline=req.payload.timeline;scene.lock_version++;result={timeline:scene.settings.timeline,lock_version:scene.lock_version};}else if(req.capability.endsWith('scene.save')){scene.settings.workspace=req.payload.workspace;scene.lock_version++;result={workspace:scene.settings.workspace,lock_version:scene.lock_version};}else if(req.capability.endsWith('music.save')){scene.settings.music=req.payload.composition;scene.settings.music_revision=(scene.settings.music_revision||0)+1;scene.lock_version++;result={composition:scene.settings.music,revision:scene.settings.music_revision,lock_version:scene.lock_version};}return route.fulfill({json:{status:'completed',result}});}
 if(u.pathname.startsWith('/lightek/')){const f=path.join(repo,'public',u.pathname);return route.fulfill({body:fs.readFileSync(f),contentType:f.endsWith('.css')?'text/css':'application/javascript'});}
 if(u.pathname==='/dashboard/studio-broadcasting/assets/100/thumbnail'){
   assert.equal(u.searchParams.get('site_id'),'2');
   const image=proofDir?fs.readFileSync(path.join(proofDir,'preview.png')):Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO8Bnj0AAAAASUVORK5CYII=','base64');
   return route.fulfill({contentType:'image/png',body:image});
 }
 if(u.pathname==='/dashboard/studio-broadcasting/assets/100/proxy'){
   assert.equal(u.searchParams.get('site_id'),'2');
   if(!proofDir)return route.fulfill({status:404});
   return route.fulfill({contentType:'model/gltf-binary',body:fs.readFileSync(path.join(proofDir,'asset.glb'))});
 }
 if(u.pathname==='/preview.png')return route.fulfill({body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==','base64'),contentType:'image/png'});
 const body=u.searchParams.get('workspace')==='stage'?html.replace('data-scene-id="1"','data-scene-id="" data-workspace="stage"'):html;
 return route.fulfill({body,contentType:'text/html'});
 });
 async function openTool(key){
   const link=page.locator(`[data-production-mode=${key}]`);
   if(!await link.isVisible())await page.locator('.production-more-tools summary').click();
   await link.click();
 }
 for(const width of [1440,1024,390]){
 await page.setViewportSize({width,height:1000});await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace/1?site_id=2#/studio/1/music');await page.locator('.music-workbench').waitFor();await page.locator('[data-music=starter]').click();
 await page.locator('.mw-track').filter({hasText:'Keys'}).click();await page.locator(`[data-music=write-note][data-pitch="${60+[1440,1024,390].indexOf(width)}"][data-step="0"]`).click();await page.locator('[data-production=save]').click();await page.waitForFunction(()=>document.querySelector('[data-music-status]').textContent.includes('saved'));
 const dimensions=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth,root:document.querySelector('#lightek-studio-dashboard').getBoundingClientRect().toJSON()}));console.log(width,JSON.stringify(dimensions));assert(dimensions.document<=width+1,'page overflow');assert.equal(await page.locator('iframe').count(),0);
 await page.screenshot({path:`${artifacts}/music-${width}.png`,fullPage:true});
 await page.evaluate(()=>window.testHeading=document.querySelector('[data-production-heading]'));
 for(const key of ['ai','workflows','edit','cast','script','deliver','scene','camera','assets','music']){if(key==='assets'&&width<=800){await openTool('media');await page.locator('.ew-library-link').click();}else await openTool(key);await page.waitForFunction(k=>document.querySelector('[data-production-shell]').dataset.mode===k,key);assert(await page.evaluate(()=>window.testHeading===document.querySelector('[data-production-heading]')),'production heading persists across modes');assert.equal(await page.locator('[data-production-heading]').count(),1);const w=await page.evaluate(()=>document.documentElement.scrollWidth);assert(w<=width+1,`${key} overflow at ${width}: ${w}`);}
 await openTool('workflows');
 await page.locator('.ai-monitor video').waitFor();
 assert.match(await page.locator('.ai-worker-status').innerText(),/18.0 \/ 24.0 GB free/);
 assert.equal(await page.locator('[name=steps]').inputValue(),'20');
 assert.equal(await page.locator('.ai-inspector [data-delivery-setting=format]').count(),1);
 assert.match(await page.locator('.ai-performance').innerText(),/MuseTalk/);
 if(width===1440){
   const nav=await page.locator('.production-sidebar').boundingBox(),controls=await page.locator('.ai-controls').boundingBox();
   const monitor=await page.locator('.ai-player').boundingBox(),inspector=await page.locator('.ai-inspector').boundingBox();
   assert(nav.x < controls.x&&controls.x < monitor.x&&monitor.x < inspector.x);
 }
 await page.locator('[data-production-mode=edit]').click();await page.locator('.ew-asset').first().click();await page.locator('[data-ew=insert]').first().click();await page.waitForFunction(()=>!LightekStudioEdit.saving()&&!LightekStudioTimeline.dirty());await page.locator('[data-ew=duplicate]').click();const draftClips=await page.evaluate(()=>LightekStudioTimeline.get().clips.length);await page.locator('[data-production-scene]').selectOption('2');await page.waitForFunction(()=>location.hash.includes('/2/'));assert.equal(await page.evaluate(()=>LightekStudioTimeline.get().clips.length),0);await page.locator('[data-production-scene]').selectOption('1');await page.waitForFunction(()=>location.hash.includes('/1/'));assert.equal(await page.evaluate(()=>LightekStudioTimeline.get().clips.length),draftClips);await page.locator('[data-production=save]').click();await page.waitForFunction(()=>!LightekStudioTimeline.dirty());
 await openTool('music');await page.locator('[data-music-track=gain]').evaluate(el=>{el.value='0.33';el.dispatchEvent(new Event('change',{bubbles:true}));});await page.locator('[data-production-scene]').selectOption('2');await page.waitForFunction(()=>location.hash.includes('/2/'));assert.equal(await page.locator('[data-music-track=gain]').inputValue(),'0.75');await page.locator('[data-production-scene]').selectOption('1');await page.waitForFunction(()=>location.hash.includes('/1/'));assert.equal(await page.locator('[data-music-track=gain]').inputValue(),'0.33');await page.locator('[data-production=save]').click();await page.waitForFunction(()=>!LightekStudioMusic.dirty());
 await openTool('script');await page.locator('[data-studio-script]').fill('Keep this scene draft');await openTool('music');await openTool('script');assert.equal(await page.locator('[data-studio-script]').inputValue(),'Keep this scene draft');
 await page.locator('[data-production-scene]').selectOption('2');await page.waitForFunction(()=>location.hash.includes('/2/'));await page.locator('[data-studio-script]').fill('Independent second scene');await page.locator('[data-production-scene]').selectOption('1');await page.waitForFunction(()=>location.hash.includes('/1/'));assert.equal(await page.locator('[data-studio-script]').inputValue(),'Keep this scene draft');await page.locator('[data-production=save]').click();await page.waitForFunction(()=>document.querySelector('[data-production-status]').textContent==='Changes saved');
 if(!await page.locator('[data-production-jobs]').evaluate(el=>el.open))await page.locator('[data-production-jobs]>summary').click();await page.locator('[data-production=use-render]').waitFor();assert.equal(await page.locator('[data-production=use-render]').count(),1,'draft previews cannot be added as finished shots');await page.locator('[data-production=use-render]').click();await page.waitForFunction(()=>document.querySelector('[data-dashboard-studio-notice]').textContent.includes('Preparing'));await page.locator('[data-production=use-render]').click();await page.waitForFunction(()=>document.querySelector('[data-production-shell]').dataset.mode==='edit');assert.equal(await page.evaluate(()=>LightekStudioTimeline.get().clips[0].asset_id),7);await openTool('script');assert.equal(await page.locator('[data-studio-script]').inputValue(),'Keep this scene draft');
 await page.locator('[data-production-mode=stage]').click();await page.locator('[data-studio-viewport-mounted]').waitFor();await page.screenshot({path:`${artifacts}/studio-${width}.png`,fullPage:true});
 }
 await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace?site_id=2&workspace=stage');
 await page.getByText('Name your scene or change its format',{exact:true}).click();
 await page.getByRole('textbox',{name:'Project name'}).fill('First animation');
 assert.equal(await page.locator('[name=format] option[value=audio]').count(),0);
 await page.getByRole('button',{name:'Start a scene'}).click();
 await page.locator('[data-vw=play-scene]').waitFor();
 assert.equal(await page.locator('[data-production-shell]').getAttribute('data-mode'),'stage');
 assert.equal(await page.getByText('Open full Blender workstation').count(),0);
 assert.equal(projectCreations,1);
 await page.locator('[data-vw-guide] [data-vw=create-photo]').click();
 const photoEditor=page.locator('dialog.vw-dialog');
 await photoEditor.getByText('Customize',{exact:true}).click();
 await photoEditor.getByRole('textbox',{name:'Character name'}).fill('Photo lead');
 await photoEditor.locator('[data-vw-character-photo]').setInputFiles({
   name:'portrait.png',mimeType:'image/png',
   buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==','base64')
 });
 await photoEditor.locator('[data-vw-photo-preview]').waitFor();
 await photoEditor.getByRole('button',{name:'Add to scene'}).click();
 await photoEditor.waitFor({state:'detached'});
 assert.equal(photoUploads,1);
 assert.equal(photoBuilds,1);
 scene.settings.studio_entry=undefined;
 await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace/1?site_id=2#/studio');await page.locator('[data-vw-form=new]').waitFor();
 await page.getByText('Project name and format',{exact:true}).click();
 const projectName=page.locator('[aria-label="Project name"]');await projectName.focus();
 for(const letter of 'New production'){
   await page.keyboard.type(letter);await page.evaluate(()=>A.studioAssetsReload());
   assert.equal(await projectName.evaluate(el=>document.activeElement===el),true,'asset refresh must not remove project-name focus');
 }
 assert.equal(await projectName.inputValue(),'New production');
 await projectName.evaluate(el=>el.setSelectionRange(4,14));await page.evaluate(()=>A.studioAssetsReload());
 assert.deepEqual(await projectName.evaluate(el=>[el.selectionStart,el.selectionEnd]),[4,14],'refresh preserves text selection');
 await page.keyboard.type('film');assert.equal(await projectName.inputValue(),'New film');
 await projectName.dispatchEvent('compositionstart');await page.evaluate(()=>window.focusTestName=document.querySelector('[aria-label="Project name"]'));await page.evaluate(()=>A.studioAssetsReload());assert(await page.evaluate(()=>window.focusTestName.isConnected),'composition keeps the original input connected');await projectName.dispatchEvent('compositionend');
 await page.locator('[data-vw-form=new] button').click();await page.locator('.edit-workbench').waitFor();assert.equal(projectCreations,2,'new production opens an edit without Blender creation');
 await openTool('script');await page.locator('[data-studio-script]').fill('');await page.locator('[data-studio-script]').focus();
 await page.keyboard.type('Writing through background updates');await page.evaluate(()=>A.studioAssetsReload());
 assert.equal(await page.locator('[data-studio-script]').evaluate(el=>document.activeElement===el),true,'script refresh must preserve focus');
 await page.keyboard.type(' without clicking');assert.equal(await page.locator('[data-studio-script]').inputValue(),'Writing through background updates without clicking');
 await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace/1?site_id=2#/studio');await page.getByText('Try an example scene',{exact:true}).click();await page.locator('[data-vw=starter-example]').click();
 await page.getByRole('link',{name:'Open character scene →'}).waitFor({timeout:12000});assert.equal(starterRequests,1);await page.getByRole('link',{name:'Open character scene →'}).click();await page.waitForFunction(()=>location.hash==='#/studio/3/stage');await page.locator('[data-studio-viewport-mounted]').waitFor();assert.equal(await page.evaluate(()=>studioSceneRecord(3).project.name),'Rain and Snow','ready starter refreshes the project inventory before opening');
 await page.goto('http://localhost:18447/dashboard/studio-broadcasting/workspace?site_id=2&workspace=stage&advanced=1#/studio/rigged');
 const builder=page.getByRole('region',{name:'Character builder'});
 await builder.getByText('Checking for saved character builds…').waitFor({state:'hidden'});
 await builder.locator('[data-vw-rig-upload]').setInputFiles({name:'guest-rig.blend',mimeType:'application/x-blender',buffer:Buffer.from('fixture')});
 try{await builder.getByText('guest-rig.blend is ready. Choose it under Starting point.').waitFor({timeout:8000});}
 catch(error){throw Error((await builder.innerText())+' · upload requests '+rigUploads+' · '+error.message);}
 await builder.getByRole('button',{name:'Create a character'}).click();
 const character=page.getByRole('dialog',{name:'Create a character'});
 const characterName=character.getByLabel('Character name');
 const saveCharacter=character.getByRole('button',{name:'Save character',exact:true});
 assert(await characterName.evaluate(input=>input===document.activeElement),'name is focused on open');
 const contrast=await saveCharacter.evaluate(button=>{
   const {color,backgroundColor}=getComputedStyle(button);
   const luminance=value=>value.match(/\d+/g).slice(0,3).map(channel=>Number(channel)/255)
     .map(channel=>channel<=.04045?channel/12.92:((channel+.055)/1.055)**2.4)
     .reduce((sum,channel,index)=>sum+channel*[.2126,.7152,.0722][index],0);
   if(backgroundColor==='rgba(0, 0, 0, 0)')return 0;
   const pair=[luminance(color),luminance(backgroundColor)].sort((a,b)=>b-a);
   return (pair[0]+.05)/(pair[1]+.05);
 });
 assert(contrast>=4.5,'Save character button has readable contrast');
 await character.getByLabel('Palette tint',{exact:true}).waitFor({state:'hidden'});
 await saveCharacter.click();
 await character.getByText('Enter a character name.').waitFor();
 assert.equal(await characterName.getAttribute('aria-invalid'),'true');
 await characterName.fill('   ');
 await saveCharacter.click();
 assert.equal(variantRequests,0,'blank names must not submit a build');
 await characterName.fill('Detective Avery');
 await character.getByText('Enter a character name.').waitFor({state:'hidden'});
 assert.equal(await character.getByLabel('Starting point').inputValue(),'library:172');
 await character.getByLabel('Starting point').selectOption('ellie_v2');
 await character.getByLabel('Starting pose').selectOption('waving');
 await character.getByText('Animation rig with selectable starting poses.').waitFor();
 await character.getByLabel('Starting point').selectOption('human_female_stylized');
 await character.getByText('Human anatomy mesh for modeling. This starting point has no animation rig.').waitFor();
 await character.getByLabel('Starting pose').waitFor({state:'hidden'});
 await character.getByLabel('Starting point').selectOption('ellie_v2');
 assert.equal(await character.getByLabel('Starting pose').inputValue(),'waving');
 await character.getByLabel('Height').fill('115');
 await character.getByLabel('Facing').selectOption('30');
 await character.getByLabel('Apply a palette tint').check();
 await character.getByLabel('Palette tint',{exact:true}).fill('#b08050');
 await saveCharacter.click();
 await character.getByText('The character worker is temporarily unavailable.').waitFor();
 assert.equal(await characterName.inputValue(),'Detective Avery');
 assert.equal(await character.getByLabel('Starting pose').inputValue(),'waving');
 assert.equal(await character.getByLabel('Height').inputValue(),'115');
 assert(await saveCharacter.isEnabled());
 await saveCharacter.click();
 await builder.getByText('Detective Avery · Building your character scene').waitFor();
 await builder.getByRole('link',{name:'Open character scene →'}).click({timeout:12000});
 await page.waitForFunction(()=>location.hash==='#/studio/4/stage');
 const savedCamera=page.getByRole('img',{name:'Camera preview of your saved character scene'});
 if(proofDir){
   const viewport=page.locator('[data-character-mesh-ready="true"]');
   await viewport.waitFor({timeout:25000});
   await page.getByRole('button',{name:'Frame character',exact:true}).click();
   await viewport.screenshot({path:path.join(artifacts,'saved-character-stage.png')});
 }else{
   await savedCamera.waitFor();
   assert(await savedCamera.evaluate(img=>img.complete&&img.naturalWidth>0),'show the saved character image if its mesh fails');
   await page.getByRole('button',{name:'Character appearance',exact:true}).click();
   const appearance=page.getByRole('dialog',{name:'Character appearance'});
   const saved=appearance.getByText('Saved. Close this panel and choose Render camera preview to see the updated character.');
   await appearance.getByLabel('Material color').fill('#ff0000');
   await appearance.getByRole('button',{name:'Save color',exact:true}).click();
   await saved.waitFor();
   await appearance.getByLabel('Shape amount').fill('0.5');
   await appearance.getByRole('button',{name:'Save face shape',exact:true}).click();
   await saved.waitFor();
   await appearance.getByRole('button',{name:'Done',exact:true}).click();
 }
 await page.locator('[data-vw-guide]').getByRole('button',{name:'Render camera preview'}).click();
 await page.getByRole('img',{name:'Rendered camera preview'}).waitFor();
 await page.locator('[data-vw-guide]').getByRole('button',{name:'Play scene',exact:true}).click();
 await page.locator('.vw-render-stage video[src="/character-preview.mp4"]').waitFor();
 assert.equal(variantRequests,2);
 scene.settings.timeline={output:'video',width:1280,height:720,clips:[]};
 editAssetReads=0;
 const editUrl='http://localhost:18447/dashboard/studio-broadcasting/workspace/1?site_id=2';
 await page.goto(editUrl+'&test=import#/studio/1/edit');
 await page.locator('.ew-quick-actions').waitFor();
 await page.locator('[data-ew-upload]').setInputFiles({name:'opening-photo.png',mimeType:'image/png',
   buffer:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==','base64')});
 await page.locator('.ew-clip').filter({hasText:'opening-photo.png'}).waitFor();
 await page.getByText('On the timeline',{exact:true}).waitFor();
 await page.waitForFunction(()=>document.querySelector('[data-production-status]').textContent==='Changes saved');
 assert.equal(editSaves,1);
 assert.equal(editUploads,1);
 await page.reload();
 await page.locator('.ew-clip').filter({hasText:'opening-photo.png'}).waitFor();
 assert.equal(await page.locator('.ew-clip').count(),1);
 await page.goto(editUrl+'&edit_asset=171#/studio/1/edit');
 await page.waitForFunction(()=>!new URLSearchParams(location.search).has('edit_asset'));
 assert.equal(await page.locator('.ew-clip').count(),1,'reopening a handoff must not duplicate the saved clip');
 await page.getByRole('navigation',{name:'Edit actions'}).getByRole('button',{name:'Export',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('[data-production-shell]').dataset.mode==='deliver');
 assert.deepEqual(errors,[]);console.log('STUDIO_BROWSER_PASS responsive navigation, draft persistence, first photo import, saved edit reload and export navigation');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1});
