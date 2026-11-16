const {chromium}=require('playwright'),fs=require('fs'),path=require('path');const root=path.resolve(__dirname,'../..');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}}),requests=[],errors=[];let retries=0,nextId=7;
 page.on('pageerror',e=>errors.push(e.message));
 const pending=id=>({text:'What should the page be called?',status:'needs_inputs',task_dialogue:{id,status:'collecting',request_text:'Add a web page',plan:[{task:'website_page',title:'Create a draft website page',inputs:{site_id:1}}],question:{field:'title',label:'What should the page be called?'},interpretation:{source:'phrases'},can_train:true}});
 const completed=id=>({text:'Assigned to Website Operator.',status:'pending',action_id:31,task_dialogue:{...pending(id).task_dialogue,status:'dispatched',question:null,can_teach:true}});
 await page.route('https://dialogue.test/**',async route=>{const url=new URL(route.request().url()),p=url.pathname;
  if(p.startsWith('/nevaeh/'))return route.fulfill({contentType:p.endsWith('.js')?'application/javascript':p.endsWith('.css')?'text/css':'image/webp',body:fs.readFileSync(root+'/public'+p)});
  if(p==='/dashboard/business')return route.fulfill({contentType:'text/html',body:'<meta name="csrf-token" content="test"><script src="/nevaeh/presence.js" defer></script><nevaeh-presence></nevaeh-presence>'});
  if(p==='/dashboard/nevaeh/context')return route.fulfill({json:{page:{area:'Business'},actions:[],guide_url:'/dashboard/nevaeh/guide'}});
  if(p==='/dashboard/nevaeh/state')return route.fulfill({json:{user:{id:42},agents:[{id:1,system_key:'nevaeh',name:'Nevaeh',role:'Coordination'}],memory:{categories:{},items:[]},actions:[],agent_workers:[],watchers:[],host_control:false,kernel:{language_models:0}}});
  if(p==='/dashboard/nevaeh/assistant')return route.fulfill({json:{state:'idle',message:'Ready'}});
  if(p==='/dashboard/nevaeh/stage')return route.fulfill({json:{lock_version:0,panels:[],active_key:null,content:null,productions:[]}});
  if(p==='/dashboard/nevaeh/actions/31')return route.fulfill({json:{id:31,status:'completed',result:{text:'Created draft page #77.',page_id:77}}});
  if(p==='/dashboard/nevaeh/ask'){
   const body=route.request().postDataJSON();requests.push(body);
   if(body.dialogue_action==='teach')return route.fulfill({json:{...completed(body.dialogue_id),text:'Wording approved.'}});
   if(body.dialogue_action==='confirm')return route.fulfill({json:{text:'Goal started.',status:'running',goal_id:8,task_dialogue:{id:9,status:'dispatched',plan:[],request_text:'Two checks',interpretation:{source:'phrases'}}}});
   if(body.q==='Two checks')return route.fulfill({json:{text:'Review the saved goal.',status:'planned',task_dialogue:{id:9,status:'ready',goal_id:8,request_text:body.q,plan:[{title:'Check payroll',inputs:{}},{title:'Review onboarding',inputs:{}}],interpretation:{source:'phrases'}}}});
   if(body.q==='Add a web page')return route.fulfill({json:pending(nextId++)});
   if(body.dialogue_action==='continue'&&retries++===0)return route.fulfill({status:503,json:{error:'Retry this reply.'}});
   if(body.dialogue_id)return route.fulfill({json:completed(body.dialogue_id)});
   throw Error('Missing dialogue identity on follow-up: '+JSON.stringify(body));
  }
  return route.fulfill({contentType:'text/html',body:fs.readFileSync(root+'/app/views/dashboard/nevaeh_os/index.html.erb','utf8').replace('<%= csrf_meta_tags %>','<meta name="csrf-token" content="test">')});
 });
 async function ask(text){await page.locator('#q').fill(text);await page.locator('#f').evaluate(e=>e.requestSubmit());}
 await page.goto('https://dialogue.test/dashboard/nevaeh');await page.getByText('Connected',{exact:true}).waitFor();await ask('Add a web page');
 await page.getByLabel('What should the page be called?',{exact:true}).fill('Running <img src=x>');
 await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByText('Retry this reply.',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Continue',exact:true}).click();await page.getByText('Teach this wording',{exact:true}).waitFor();
 const attempts=requests.filter(r=>r.dialogue_action==='continue');if(attempts.length!==2||attempts[0].request_key!==attempts[1].request_key||attempts[1].dialogue_id!==7)throw Error('Follow-up retry lost identity');
 if(await page.locator('#task-dialogue img').count())throw Error('Task text became HTML');
 await page.getByText('Teach this wording',{exact:true}).click();if(await page.locator('#task-dialogue input').inputValue()!=='Add a web page')throw Error('Teaching lost the original request');
 await page.getByRole('button',{name:'Approve this wording',exact:true}).click();await page.getByText('Wording approved.',{exact:true}).waitFor();
 await ask('Add a web page');await page.getByLabel('What should the page be called?',{exact:true}).waitFor();await page.reload();await page.getByText('Connected',{exact:true}).waitFor();await ask('Resume after reload');await page.getByText('Teach this wording',{exact:true}).waitFor();
 if(requests.at(-1).dialogue_id!==8)throw Error('Reload lost the account-scoped active dialogue');
 await ask('Two checks');await page.getByRole('button',{name:'Start goal',exact:true}).waitFor();if(requests.some(r=>r.dialogue_action==='confirm'))throw Error('Rendering a plan dispatched it');
 await page.getByRole('button',{name:'Start goal',exact:true}).click();await page.getByText('Goal started.',{exact:true}).waitFor();
 await page.setViewportSize({width:390,height:844});await ask('Add a web page');await page.getByLabel('What should the page be called?',{exact:true}).waitFor();
 if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('Task controls overflow on mobile');await page.screenshot({path:'/tmp/nevaeh-ten-tasks-mobile.png',fullPage:true});
 await page.goto('https://dialogue.test/dashboard/business');await page.getByRole('button',{name:'Open Nevaeh assistant',exact:true}).click();
 const dock=page.locator('nevaeh-presence');await dock.getByLabel('Ask Nevaeh',{exact:true}).fill('Add a web page');await dock.locator('form').first().evaluate(e=>e.requestSubmit());
 await dock.getByLabel('What should the page be called?',{exact:true}).fill('Dock-created draft');await dock.getByRole('button',{name:'Continue',exact:true}).click();await dock.getByText('Teach this wording',{exact:true}).waitFor();
 if(!requests.at(-1).dialogue_id||requests.at(-1).dialogue_values?.title!=='Dock-created draft')throw Error('Dock follow-up lost its persisted request');
 if(errors.length)throw Error(errors.join('\n'));console.log('PASS: task follow-up form, stable retry identity, literal text, reviewed teaching, account-scoped reload, explicit goal start and mobile layout');
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1)});
