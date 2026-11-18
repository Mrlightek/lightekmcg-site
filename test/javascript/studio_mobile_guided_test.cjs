/* Run the shipped PWA, its complete script chain and actual viewport against API fixtures. */
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
async function check(){
 let scene=null;
 const requests=[],errors=[];
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-webgl']});
 try{
 const page=await browser.newPage({viewport:{width:390,height:844}});page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://studio.test/**',async route=>{
  const url=new URL(route.request().url());
  const json=result=>route.fulfill({contentType:'application/json',body:JSON.stringify(result)});
  if(url.pathname==='/api/nevaeh/bootstrap')return json({identity:{id:1,profile:{id:1,name:'Studio tester',profile_type:'creator'}},navigation:[],surfaces:[],capabilities:[]});
  if(url.pathname==='/api/nevaeh/execute'){
   const request=route.request().postDataJSON();requests.push(request);const {capability,payload}=request;let result={};
   if(capability==='studio.pwa.bootstrap')result={projects:scene?[{id:1,name:scene.name,productions:[],unassigned_scenes:[scene]}]:[],object_types:['cube','sphere','cylinder','camera']};
   else if(capability.endsWith('project.create')){scene={id:2,name:payload.name,lock_version:0,objects:[],settings:{studio_entry:'stage'}};result={scene_id:2};}
   else if(capability.endsWith('cast.create'))result={asset_id:77,status:'processing'};
   else if(capability.endsWith('cast.place')){assert.equal(payload.asset_id,77);assert.equal(payload.scene_id,2);scene.objects.push({id:5,name:'Explorer',object_type:'cube',definition:{character_profile:{motions:[{id:'wave',name:'Wave',fps:24,frame_start:1,frame_end:25}]}}});result={object_id:5};}
   else if(capability.endsWith('motion.save')){scene.objects[0].definition.motion_clips=payload.clips;result={};}
   else if(capability.endsWith('performance.preview'))result={status:'completed',url:'/draft.mp4'};
   else if(capability.endsWith('assets.list'))result={assets:requests.some(r=>r.capability.endsWith('cast.create'))?[{id:77,name:'Explorer',kind:'blend',status:'ready',metadata:{character_profile:{}}}]:[],builtins:[],media_presets:[],camera_presets:[],blender_demos:[]};
   return json({status:'completed',result});
  }
  const file=path.join('public',url.pathname==='/'?'/lightek/index.html':url.pathname);
  if(fs.existsSync(file)&&fs.statSync(file).isFile())return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.html')?'text/html':'image/svg+xml'});
  return route.fulfill({status:404,body:''});
 });

 await page.goto('https://studio.test/lightek/index.html#/studio');
 const start=page.getByRole('button',{name:'Start a scene'});
 await start.waitFor();
 const name=page.getByRole('textbox',{name:'Project name'});
 assert.equal(await name.isVisible(),false);
 await page.getByText('Name your scene or change its format',{exact:true}).click();
 await name.fill('My phone scene');
 await name.focus();
 await name.evaluate(el=>{window.initialName=el;el.setSelectionRange(3,8);});
 await page.evaluate(async()=>{ST.loaded=false;await A.studioLoad(true);render(1);});
 assert(await name.evaluate(el=>el===window.initialName&&el===document.activeElement&&el.selectionStart===3&&el.selectionEnd===8));
 assert.equal(await name.inputValue(),'My phone scene');
 await name.fill('');
 await start.click();
 await page.getByText('Who’s in your scene?',{exact:true}).waitFor();
 assert.equal(requests.find(r=>r.capability.endsWith('project.create')).payload.name,'My scene');
 const stage=page.locator('.studio-viewport');
 await stage.waitFor();
 const canvas=await stage.boundingBox();
 assert(canvas.width>=360 && canvas.height>=290, JSON.stringify(canvas));
 assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.getByRole('button',{name:'Pick a character'}).click();
 await page.getByText('Explorer',{exact:true}).click();
 assert.equal(await page.getByRole('textbox',{name:'Character name'}).isVisible(),false);
 await page.getByRole('button',{name:'Add to scene',exact:true}).click();
 await page.getByRole('button',{name:'Choose an action',exact:true}).click();
 await page.getByRole('button',{name:'Wave',exact:true}).click();
 await page.locator('[data-vw-guide]').getByRole('button',{name:'Play scene',exact:true}).click();
 await page.locator('.vw-render-stage video').waitFor();
 assert.equal(requests.filter(r=>r.capability.endsWith('cast.place')).length,1);
 assert.deepEqual(errors,[]);
 console.log('MOBILE_GUIDED_STUDIO_PASS physical-width stage, stable typing, visual choices, auto-place and preview');
 }finally{await browser.close();}
}
check().catch(error=>{console.error(error);process.exitCode=1;});
