// Browser integration test for real PWA markup and client/server contracts.
// API fixtures isolate browser behavior; database behavior is tested separately.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve('public');
const shell=JSON.parse(fs.readFileSync(path.join(root,'lightek/sw.js'),'utf8').match(/const SHELL = (\[[\s\S]*?\n\])/)[1]);
for(const asset of shell)assert.ok(fs.existsSync(path.join(root,asset)),`Offline shell dependency must exist: ${asset}`);
const identity = { id: 1, authenticated: true, profile: {id:1,name:'Marlon',display_handle:'@marlon',profile_type:'person',sections:[{key:'posts'},{key:'communities'},{key:'about'}]} };
let communities = [{id:1,slug:'lightek-creators',name:'Lightek Creators',description:'Our network',visibility:'public',sections:['conversations','members','about'],member_count:2,joined:true,can_manage:true,owner:identity.profile}];
let posts = [{id:1,title:'The first production',content:'Published by the network',kind:'post',visibility:'public',author:identity.profile,created_at:new Date().toISOString(),reply_count:0,like_count:0,rsvp_count:0,engagements:[],media:[],can_delete:true}];
const scene = {id:1,studio_project_id:1,production_id:1,name:'Pilot Scene',settings:{workspace:{}},lock_version:0,object_count:1,objects:[{id:1,name:'Hero Cube',object_type:'cube',definition:{location:[0,0,0],rotation:[0,0,0],scale:[1,1,1]}}]};
const production = {id:1,name:'Pilot',status:'development',scenes:[scene]};
const project = {id:1,name:'Lightek Production',description:'Pilot',productions:[production],scenes:[scene],unassigned_scenes:[]};
const featured={id:2,name:'Alicia',display_handle:'@alicia',profile_type:'person'};
let topPeople=[],topLimit=8,gender='unspecified';
const asset={id:1,name:'Camera take',kind:'video',status:'ready',metadata:{duration:2,has_audio:true},proxy_url:'/test-take.mp4'};
let application=null,disabledSurfaces=[];
const errors=[], writes=[];
const server=http.createServer((req,res)=>{
  const file=path.join(root,new URL(req.url,'http://local').pathname);
  if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return}
  fs.readFile(file,(err,data)=>{if(err){res.writeHead(404).end();return}res.setHeader('Content-Type',file.endsWith('.html')?'text/html':file.endsWith('.css')?'text/css':file.endsWith('.js')?'text/javascript':'application/octet-stream');res.end(data)});
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--disable-gpu']});
  const context=await browser.newContext({serviceWorkers:'block'});
  await context.route('**/api/**',async route=>{
    const url=new URL(route.request().url());
    let body={};
    if(url.pathname.endsWith('/bootstrap')) body={application,identity,csrf_token:'token',surfaces:['home','watch','clips','explore','communities','space','create','messages','studio'].filter(key=>!disabledSurfaces.includes(key)).map(key=>({key})),navigation:['home','watch','clips','explore','communities'].filter(key=>!disabledSurfaces.includes(key)).map((key,i)=>({key,label:key,surface_id:key,href:`#/${key}`,placement:'primary'})),capabilities:[],services:[{label:'Marketplace',href:'/marketplace'}]};
    else if(url.pathname.endsWith('/pwa')) {
      const view=url.searchParams.get('view');
      if(view==='communities')body={communities};
      else if(view==='community')body={community:communities[0],posts,members:[identity.profile]};
      else if(view==='post')body={post:posts.find(p=>p.id==url.searchParams.get('id')),posts:[]};
      else if(view==='profile')body={profile:identity.profile,posts,communities,top_people:topPeople,top_people_limit:topLimit,profile_preferences:{community_gender:gender}};
      else if(view==='explore')body={people:[identity.profile,featured],communities,posts};
      else body={posts,next_before:null};
    } else if(url.pathname.endsWith('/execute')) {
      const request=route.request().postDataJSON(); writes.push(request);
      const p=request.payload;
      if(request.capability==='studio.workspace.assets.list')body={status:'completed',result:{assets:[asset]}};
      else if(request.capability==='community.top.people.save'){topPeople=p.profile_ids.map(id=>featured);topLimit=p.limit;body={status:'completed',result:{}};}
      else if(request.capability==='community.profile.preferences'){gender=p.community_gender;body={status:'completed',result:{}};}
      else if(request.capability==='studio.workspace.timeline.save'){scene.settings.timeline=p.timeline;scene.lock_version++;body={status:'completed',result:{timeline:p.timeline,lock_version:scene.lock_version}};}
      else if(request.capability==='studio.pwa.bootstrap')body={status:'completed',result:{projects:[project],object_types:['cube','camera']}};
      else if(request.capability==='studio.workspace.scene.save'){
        scene.settings.workspace=p.workspace;scene.lock_version++;body={status:'completed',result:{scene_id:1,lock_version:scene.lock_version,workspace:p.workspace}};
      }else if(request.capability==='community.post.create') {
        const post={...posts[0],id:posts.length+1,title:p.title,content:p.content};posts.unshift(post);body={status:'completed',result:{post}};
      }else if(request.capability==='community.engage'){
        const post=posts.find(x=>x.id===p.post_id);post.like_count=p.active?1:0;post.engagements=p.active?[p.kind]:[];body={status:'completed',result:{post}};
      } else if(request.capability==='community.update'){communities[0]={...communities[0],...p};body={status:'completed',result:{community:communities[0]}}}
      else body={status:'completed',result:{}};
    }
    await route.fulfill({json:body});
  });
  const page=await context.newPage();
  page.on('pageerror',error=>errors.push(error.message));
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/home`);
  await page.getByText('The first production',{exact:true}).waitFor();
  assert.equal(await page.getByText('Diaspora Kitchens',{exact:true}).count(),0);
  await page.getByRole('link',{name:'Create',exact:true}).click();
  await page.getByRole('textbox',{name:'Title',exact:true}).fill('A real post');
  await page.getByRole('textbox',{name:'Tell the story'}).fill('Saved through Nevaeh');
  await page.getByRole('button',{name:'Publish',exact:true}).click();
  await page.getByText('A real post',{exact:true}).waitFor();
  assert.equal(writes[0].capability,'community.post.create');
  assert.match(writes[0].payload.request_key,/^[a-z0-9-]+$/i);
  await page.getByRole('button',{name:/♡ Like/}).first().click();
  await page.getByRole('button',{name:/♥ Liked/}).waitFor();
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/communities`);
  await page.getByRole('heading',{name:'Lightek Creators'}).waitFor();
  await page.getByRole('heading',{name:'Lightek Creators'}).click();
  await page.getByText('Community settings',{exact:true}).click();
  await page.getByRole('textbox',{name:'Name',exact:true}).fill('Lightek Community');
  await page.getByRole('button',{name:'Save settings'}).click();
  await page.getByRole('heading',{name:'Lightek Community',exact:true}).waitFor();
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/space/1`);
  await page.locator('[data-top-limit]').waitFor();
  await page.locator('[data-top-limit]').selectOption('5');
  await page.getByRole('searchbox',{name:'Find friends or other people'}).fill('Alicia');
  await page.getByRole('button',{name:'Find people',exact:true}).click();
  await page.getByRole('button',{name:'Feature this person'}).click();
  await page.getByRole('button',{name:'Save my Top 5'}).click();
  await page.getByRole('heading',{name:'My Top 5'}).waitFor();
  assert.deepEqual(writes.find(w=>w.capability==='community.top.people.save').payload,{limit:5,profile_ids:[2]});
  await page.getByText('Private audience access',{exact:true}).click();
  await page.locator('select[name="community_gender"]').selectOption('woman');
  await page.getByRole('button',{name:'Save setting',exact:true}).click();
  await page.waitForFunction(()=>document.querySelector('select[name="community_gender"]')?.value==='woman');
  assert.equal(writes.find(w=>w.capability==='community.profile.preferences').payload.community_gender,'woman');
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:'/tmp/lightek-community-mobile.png',fullPage:true});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'mobile page must not overflow');
  await page.setViewportSize({width:1440,height:1000});
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/studio/1`);
  await page.getByRole('heading',{name:'Pilot Scene',exact:true,level:1}).waitFor();
  await page.getByRole('button',{name:'Script',exact:true}).first().click();
  await page.locator('[data-studio-script]').fill('INT. LIGHTEK STUDIO — NIGHT\nA creator builds the network.');
  await page.getByRole('button',{name:'Save workspace',exact:true}).click();
  await page.getByText('Saved to your account',{exact:true}).waitFor();
  const saved=writes.find(w=>w.capability==='studio.workspace.scene.save');
  assert.match(saved.payload.workspace.story.scriptDraft,/A creator builds the network/);
  await page.reload();
  await page.getByRole('heading',{name:'Pilot Scene',exact:true,level:1}).waitFor();
  await page.getByRole('button',{name:'Script',exact:true}).first().click();
  assert.match(await page.locator('[data-studio-script]').inputValue(),/A creator builds the network/);
  await page.getByRole('button',{name:'Timeline',exact:true}).first().click();
  await page.getByRole('button',{name:'Add clip',exact:true}).click();
  await page.getByRole('button',{name:'Add keyframe',exact:true}).click();
  await page.locator('[data-frame-field="x"]').fill('24');
  await page.getByRole('button',{name:'Save timeline',exact:true}).click();
  await page.waitForFunction(()=>document.body.textContent.includes('Timeline saved'));
  const edited=writes.find(w=>w.capability==='studio.workspace.timeline.save');
  assert.equal(edited.payload.timeline.clips[0].keyframes[0].x,24);
  await page.reload();
  await page.getByRole('heading',{name:'Pilot Scene',exact:true,level:1}).waitFor();
  await page.getByRole('button',{name:'Timeline',exact:true}).first().click();
  assert.equal(await page.locator('[data-frame-field="x"]').inputValue(),'24');
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/studio/library`);
  await page.getByRole('heading',{name:'Asset Library',exact:true}).waitFor();
  await page.getByRole('heading',{name:'Camera take',exact:true}).waitFor();
  application={name:'Dymondcutz',short_name:'Dymond',status:'published',theme_color:'#dd7722',background_color:'#161121',start_surface:'home',administration:{super_admin:false,can_manage:true}};
  disabledSurfaces=['clips'];
  await page.goto(`http://127.0.0.1:${server.address().port}/lightek/index.html#/home`);
  await page.reload();
  await page.waitForFunction(()=>document.title==='Dymondcutz');
  assert.equal(await page.locator('#top .logo').textContent(),'Dymondcutz');
  assert.equal(await page.locator('#primary-nav [data-r="clips"]').count(),0);
  assert.equal(await page.evaluate(()=>document.documentElement.style.getPropertyValue('--gd')),'#dd7722');
  application.status='maintenance';
  await page.reload();
  await page.getByRole('heading',{name:'Dymondcutz is under maintenance',exact:true}).waitFor();
  await page.getByRole('link',{name:'Open PWA Administration',exact:true}).waitFor();
  assert.deepEqual(errors,[]);
  console.log('PWA browser: feed, post publish, reactions, community settings, mobile layout, Top 5, private audience preferences, Studio save/reload, timeline keyframes, and asset library passed.');
  await browser.close();server.close();
})().catch(err=>{console.error(err);server.close();process.exit(1)});
