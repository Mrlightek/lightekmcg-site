const {chromium}=require('playwright'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..');
(async()=>{
  const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{}),args:['--no-sandbox']});
  try{
    const page=await browser.newPage(),sent=[],queries=[],errors=[];let feedback=null;
    page.on('pageerror',e=>{errors.push(e.message);console.error(e.message);});
    const report={id:8,agent_id:4,agent:'Mail Operator',capability:'messages.list',site:'7',status:'completed',receipt_sha256:'a'.repeat(64),evidence:{action_id:21,run_id:5,chain:[{id:21,status:'completed'},{id:90,type:'dispatch',status:'completed'}]}};
    report.structured_report={...JSON.parse(fs.readFileSync(root+'/docs/nevaeh/tutorials/reporting_system.md','utf8').match(/```json\n([\s\S]*?)\n```/)[1]),task_id:'run-5'};
    await page.route('https://reports.test/**',async route=>{
      const url=new URL(route.request().url());
      if(url.pathname.startsWith('/nevaeh/'))return route.fulfill({contentType:url.pathname.endsWith('.css')?'text/css; charset=utf-8':'application/javascript; charset=utf-8',body:fs.readFileSync(root+'/public'+url.pathname)});
      if(url.pathname==='/dashboard/nevaeh/worker_reports/8/reviews'){
        if(route.request().headers()['x-csrf-token']!=='test')throw Error('Missing feedback CSRF');
        const value=route.request().postDataJSON();sent.push(value);feedback={...value,id:1};return route.fulfill({json:{...report,review:feedback}});
      }
      if(url.pathname==='/dashboard/nevaeh/worker_reports'){queries.push(url.search);return route.fulfill({json:{reports:[{...report,review:feedback}],total:1,scope:'Your account; latest 40 reports.',learning:'Service completion and owner acceptance are separate.'}});}
      return route.fulfill({contentType:'text/html; charset=utf-8',body:'<meta charset="utf-8"><meta name="csrf-token" content="test"><link rel="stylesheet" href="/nevaeh/os.css"><link rel="stylesheet" href="/nevaeh/workforce.css"><div id="root" class="workforce" style="max-width:1000px;margin:auto"></div><script>async function api(p,method="GET",data){const r=await fetch("/dashboard/nevaeh"+p,{method,headers:{"Content-Type":"application/json","X-CSRF-Token":"test"},body:data?JSON.stringify(data):undefined});return r.json();}</script><script src="/nevaeh/reports.js"></script><script>NevaehReports.mount(document.querySelector("#root"),[{id:4,name:"Mail Operator"},{id:9,name:"Finance Operator"}]);</script>'});
    });
    await page.goto('https://reports.test/dashboard/nevaeh');
    await page.getByText('#8 · Mail Operator',{exact:true}).waitFor();
    await page.getByText('No current owner review. Service completion does not establish output quality.',{exact:true}).waitFor();
    await page.getByText('Worker JSON report · schema v1',{exact:true}).click();await page.getByText(/"task_id": "run-5"/).waitFor();
    const link=page.getByRole('link',{name:'Open actual execution receipt'});if(await link.getAttribute('href')!=='/dashboard/nevaeh/actions/21')throw Error('Missing actual receipt reference');
    await page.getByText('Review result or teach this specialist',{exact:true}).click();
    await page.getByLabel('Review verdict for report 8',{exact:true}).selectOption('needs_fix');
    const lesson='Check filters first. <img src=x onerror=alert(1)>';
    await page.getByLabel('Lesson or correction',{exact:true}).fill(lesson);
    await Promise.all([page.waitForResponse(r=>r.url().endsWith('/worker_reports/8/reviews')),page.getByRole('button',{name:'Save review',exact:true}).click()]);
    if(sent.length!==1||sent[0].verdict!=='needs_fix'||sent[0].lesson!==lesson||sent[0].receipt_sha256!==report.receipt_sha256)throw Error('Feedback lost verdict, lesson or evidence binding');
    await page.getByLabel('Filter reports by specialist',{exact:true}).selectOption('4');
    await page.getByText('Owner review: needs_fix',{exact:true}).waitFor();
    if(!queries.includes('?agent_id=4'))throw Error('Specialist filter not sent');
    if(await page.locator('img').count())throw Error('Lesson markup was interpreted as HTML');
    await page.screenshot({path:'/tmp/nevaeh-sme-reports-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth))throw Error('Reports overflow on mobile');await page.screenshot({path:'/tmp/nevaeh-sme-reports-mobile.png',fullPage:true});
    if(errors.length)throw Error(errors.join('\n'));
    console.log('PASS: specialist reports, completion/acceptance distinction, receipt references, scoped filter, evidence-bound feedback and escaped lessons');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
