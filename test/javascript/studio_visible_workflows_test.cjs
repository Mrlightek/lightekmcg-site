/* Run the shipped PWA, its complete script chain and actual viewport against API fixtures. */
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
const original=JSON.parse(fs.readFileSync('config/studio/packs/original_media.json','utf8'));
const bible=original.find(item=>item.key==='nwo/show_bible');
const resolved={...bible.definition,body:{...original[0].definition.body,...bible.definition.body}};
const character=()=>['Head','Torso','Left arm','Right arm','Left leg','Right leg'].map((part,i)=>({id:i+1,name:`Iris · ${part}`,object_type:i===0?'sphere':i===1?'cube':'cylinder',definition:{body_part:part.toLowerCase(),character_key:'iris',library_instance:'iris-instance',category:'characters',location:[[0,0,2.5],[0,0,1.8],[-.45,0,1.8],[.45,0,1.8],[-.18,0,.8],[.18,0,.8]][i],rotation:[0,0,0],scale:[[.25,.25,.3],[.3,.18,.4],[.1,.1,.4],[.1,.1,.4],[.13,.13,.5],[.13,.13,.5]][i],material:{color:[.25,.65,.7,1]}}}));
async function check(software){
 let scene={id:1,name:'Visible character scene',lock_version:0,object_count:6,objects:character(),settings:{render_engine:'BLENDER_EEVEE_NEXT',resolution_x:1280,resolution_y:720,blender_presets:[{key:bible.key,title:resolved.title,definition:resolved}]}};
 const requests=[],errors=[];
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process',...(software?['--disable-webgl']:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader'])]});
 try{
 const page=await browser.newPage({viewport:{width:1440,height:1100}});page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://studio.test/**',async route=>{
  const url=new URL(route.request().url());
  const json=result=>route.fulfill({contentType:'application/json',body:JSON.stringify(result)});
  if(url.pathname==='/api/nevaeh/bootstrap')return json({identity:{id:1,profile:{id:1,name:'Studio tester',profile_type:'creator'}},navigation:[],surfaces:[],capabilities:[]});
  if(url.pathname==='/api/nevaeh/execute'){
   const request=route.request().postDataJSON();requests.push(request);const {capability,payload}=request;let result={};
   if(capability==='studio.pwa.bootstrap')result={projects:[{id:1,name:'Visible workflows',productions:[],unassigned_scenes:[scene]}],object_types:['cube','sphere','cylinder','camera']};
   else if(capability.endsWith('assets.list'))result={assets:[],builtins:[{key:'char_iris',name:'Iris',category:'characters',description:'Editable blocking mannequin.',target:'scene'},{key:'tpl_live_interview',name:'Live Interview',category:'templates',description:'Characters, cameras and audio.',target:'scene'}],media_presets:[{key:bible.key,name:resolved.title,category:'show_bible',description:'Creative direction.'}],camera_presets:[],blender_demos:[]};
   else if(capability==='studio.scene_object.transform'){const object=scene.objects.find(o=>o.id===payload.object_id);Object.assign(object.definition,payload.attributes);object.name=payload.attributes.name;scene.lock_version++;result={scene_id:1,object_id:object.id,mutation:'updated'};}
   else if(capability.endsWith('workspace.scene.save')){scene.settings.workspace=payload.workspace;scene.lock_version++;result={workspace:payload.workspace,lock_version:scene.lock_version};}
   else if(capability.endsWith('blender.preset.use')){scene.settings.blender_presets.push({key:bible.key,title:resolved.title,definition:resolved});scene.lock_version++;result={scene_id:1,lock_version:scene.lock_version};}
   else if(capability.endsWith('library.apply')){const added=character().map(o=>({...o,id:o.id+20,definition:{...o.definition,library_instance:'second-iris'}}));scene.objects.push(...added);scene.object_count=scene.objects.length;scene.lock_version++;result={scene_id:1,object_ids:added.map(o=>o.id),asset_ids:payload.key==='tpl_live_interview'?[40]:[]};}
   return json({status:'completed',result});
  }
  const file=path.join('public',url.pathname==='/'?'/lightek/index.html':url.pathname);
  if(fs.existsSync(file)&&fs.statSync(file).isFile())return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'image/svg+xml'});
  return route.fulfill({status:404,body:''});
 });
 await page.goto('https://studio.test/lightek/index.html#/studio/1');
 await page.locator('.studio-viewport-canvas canvas').waitFor();
 assert.equal(await page.locator('.studio-start-guide').count(),1);
 assert.match(await page.getByLabel('Scene Outliner').innerText(),/Iris · blocking mannequin/);
 if(software){await page.waitForFunction(()=>Number(document.querySelector('[data-studio-software]')?.dataset.drawnFaces)>100);assert.match(await page.locator('.studio-viewport-status').innerText(),/Software layout/);}
 else assert.equal(await page.locator('[data-studio-software]').count(),0);
 const canvas=page.locator('.studio-viewport-canvas canvas');
 await canvas.screenshot({path:`/tmp/studio-${software?'software':'webgl'}-before.png`});
 await page.getByLabel('Scene Outliner').getByRole('button',{name:'torso',exact:true}).click();
 assert.match(await page.locator('.studio-live-inspector').innerText(),/Editing Iris · torso/);
 const beforeEdit=await canvas.screenshot();
 await page.locator('[data-studio-form=inspector] [name=scale_0]').fill('1.3');
 await page.getByRole('button',{name:'Save element',exact:true}).click();
 await page.waitForFunction(()=>document.querySelector('[data-studio-form=inspector] [name=scale_0]')?.value==='1.3'&&!document.querySelector('[data-studio-form=inspector] button')?.disabled);
 assert.equal(requests.find(r=>r.capability==='studio.scene_object.transform').payload.attributes.scale[0],1.3);
 const afterEdit=await canvas.screenshot({path:`/tmp/studio-${software?'software':'webgl'}-after.png`});assert(!beforeEdit.equals(afterEdit),'saved scale must visibly change the rendered character');
 await page.screenshot({path:`/tmp/studio-${software?'software':'webgl'}-page.png`,fullPage:true});
 // An empty transform is rejected by browser validation, instead of becoming an implicit zero.
 const count=requests.length;await page.locator('[name=scale_0]').fill('');await page.getByRole('button',{name:'Save element',exact:true}).click();assert.equal(requests.length,count);
 await page.locator('[name=scale_0]').fill('1.3');
 await page.locator('.studio-work-tabs [data-mode=visual]').first().click();
 await page.getByRole('button',{name:'Save visual settings',exact:true}).click();
 await page.waitForFunction(()=>!document.querySelector('[data-studio-form=visual] button')?.disabled);
 const visual=requests.find(r=>r.capability.endsWith('visual.save'));assert.deepEqual(Object.keys(visual.payload.properties),['color'],'only properties actually shown for this element should be submitted');
 await page.locator('[data-a=studioWorkspaceMode][data-mode=script]').first().click();
 assert.match(await page.locator('[data-show-bible]').innerText(),/covert Afrofuturist/);
 const draft=page.locator('[data-studio-script]');assert.match(await draft.inputValue(),/SCENE OUTLINE/);assert.match(await draft.inputValue(),/They hoarded the future/);
 await draft.fill('INT. STUDIO — DAY\nIRIS: This is my scene.');
 await page.getByRole('button',{name:'Save workspace',exact:true}).click();await page.getByText('Saved to your account',{exact:true}).waitFor();
 await page.reload();await page.locator('.studio-viewport-canvas canvas').waitFor();await page.locator('[data-a=studioWorkspaceMode][data-mode=script]').first().click();
 assert.equal(await page.locator('[data-studio-script]').inputValue(),'INT. STUDIO — DAY\nIRIS: This is my scene.');
 await page.getByText('Add a preset or render a Blender camera preview',{exact:true}).click();
 await page.getByRole('button',{name:'Apply to this scene / selected element',exact:true}).click();
 await page.locator('[data-studio-outcome]').waitFor();assert.equal(await page.locator('[data-studio-script]').inputValue(),'INT. STUDIO — DAY\nIRIS: This is my scene.');assert.match(await page.locator('[data-studio-outcome]').innerText(),/Show bible applied/);
 // Quick character application returns to the actual layout and selects the newly added shape.
 await page.evaluate(()=>A.studioBuiltinQuick({dataset:{key:'char_iris'}}));
 await page.locator('.studio-viewport-canvas canvas').waitFor();assert.match(await page.locator('[data-studio-outcome]').innerText(),/6 scene elements added/);
 assert.equal(await page.getByLabel('Scene Outliner').locator('[aria-pressed=true]').textContent(),'head');
 await page.locator('.studio-work-head').getByRole('link',{name:'Library',exact:true}).click();
 await page.getByRole('button',{name:'Presets & recipes',exact:true}).click({timeout:5000});
 await page.locator('[data-library-key=tpl_live_interview]').getByRole('button',{name:'Add to scene',exact:true}).click();
 await page.locator('.studio-viewport-canvas canvas').waitFor();
 assert.match(await page.locator('[data-studio-outcome]').innerText(),/6 scene elements added/,'a package containing media must still show its character geometry');
 await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'mobile page must not overflow');
 assert.deepEqual(errors,[]);
 console.log(`STUDIO_VISIBLE_WORKFLOWS_PASS ${software?'software':'webgl'} full_pwa character_selection saved_transform bible_recovery draft_preservation apply_outcomes mobile`);
 }finally{await browser.close();}
}
(async()=>{await check(true);await check(false);})().catch(error=>{console.error(error);process.exitCode=1;});
