// Browser QA of actual dashboard ERB captured by pwa_administration_checks.rb.
const {chromium}=require('playwright');
const fs=require('node:fs'),http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const capture=process.env.PWA_ADMIN_CAPTURE_DIR||'/tmp/lightek-pwa-dashboard';
const requests=[],errors=[];
const server=http.createServer((req,res)=>{
  const url=new URL(req.url,'http://local');
  if(req.method==='POST'){
    let data='';req.on('data',chunk=>data+=chunk);req.on('end',async()=>{const parsed=(req.headers['content-type']||'').includes('multipart/form-data')?await new Request('http://local',{method:'POST',headers:{'Content-Type':req.headers['content-type']},body:data}).formData():new URLSearchParams(data);requests.push(parsed);res.writeHead(303,{Location:'/dashboard/pwa?section=settings'});res.end();});return;
  }
  const section=url.searchParams.get('section')||'overview';
  if(!/^[a-z]+$/.test(section)){res.writeHead(400).end();return;}
  fs.readFile(path.join(capture,section+'.html'),(error,body)=>{if(error){res.writeHead(404).end();return;}res.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});res.end(body);});
});
(async()=>{
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_EXECUTABLE_PATH,args:['--no-sandbox','--disable-dev-shm-usage','--use-gl=angle','--use-angle=swiftshader','--disable-gpu']});
  const page=await browser.newPage({viewport:{width:1440,height:1050}});
  page.on('pageerror',error=>errors.push(error.message));
  const base=`http://127.0.0.1:${server.address().port}/dashboard/pwa`;
  await page.goto(base);
  await page.getByRole('heading',{name:'PWA Administration',exact:true}).waitFor();
  assert.equal(await page.locator('.pa-metric').count(),8);
  await page.screenshot({path:'/tmp/lightek-pwa-dashboard-desktop.png',fullPage:true});
  await page.getByRole('link',{name:'Settings',exact:true}).click();
  await page.getByLabel('Application name',{exact:true}).fill('Tiffany Community');
  await page.getByLabel('Home-screen name').fill('Tiffany');
  await page.locator('details').filter({has:page.locator('summary',{hasText:'Watch'})}).first().evaluate(el=>el.open=true);
  await page.getByRole('checkbox',{name:'Enable Watch',exact:true}).uncheck();
  await page.getByRole('button',{name:'Save PWA settings',exact:true}).click();
  await page.waitForURL('**section=settings');
  assert.equal(requests.at(-1).get('application[name]'),'Tiffany Community');
  assert.equal(requests.at(-1).getAll('application[surfaces][watch][enabled]').at(-1),'0');
  await page.setViewportSize({width:390,height:844});
  await page.goto(base+'?section=settings');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'dashboard must fit mobile width');
  await page.screenshot({path:'/tmp/lightek-pwa-dashboard-mobile.png',fullPage:true});
  await page.goto(base+'?section=content');
  await page.getByText('The first network story',{exact:false}).first().click();
  await page.getByLabel('Moderation',{exact:true}).selectOption('hidden');
  await page.getByRole('button',{name:'Save post',exact:true}).click();
  assert.equal(requests.at(-1).get('record[moderation_state]'),'hidden');
  assert.deepEqual(errors,[]);
  await browser.close();server.close();
  console.log('PWA dashboard browser: actual overview/settings/content, form contracts, brand editing, feature toggle, moderation, desktop and mobile passed.');
})().catch(error=>{console.error(error);server.close();process.exit(1)});
