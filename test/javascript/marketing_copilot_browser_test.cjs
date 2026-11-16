const {chromium}=require('playwright'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try{
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  const preview=process.env.MARKETING_PREVIEW_PATH||root+'/tmp/marketing-copilot-preview.html';
  await page.route('https://marketing.test/**',route=>{
   const url=new URL(route.request().url());
   if(url.pathname.startsWith('/lightek/'))return route.fulfill({contentType:'text/css',body:fs.readFileSync(root+'/public'+url.pathname)});
   return route.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync(preview,'utf8')});
  });
  await page.goto('https://marketing.test/dashboard/marketing-copilot');
  await page.addStyleTag({content:'body{margin:0;background:#15121b;font-family:system-ui,sans-serif}'});
  await page.getByRole('heading',{name:'Know your next move.'}).waitFor();
  await page.getByLabel('Time per day').selectOption('15');
  await page.getByLabel('Where will you share it?').selectOption('linkedin');
  await page.getByLabel('Customer destination',{exact:false}).fill('/contact');
  const form=page.locator('form').filter({has:page.getByRole('button',{name:'Prepare my seven-day kit'})});
  const fields=await form.evaluate(element=>Object.fromEntries(new FormData(element)));
  if(fields['kit[minutes_per_day]']!=='15'||fields['kit[source]']!=='linkedin'||!fields.request_key)throw Error('Marketing inputs or retry key missing');
  const firstDay=page.locator('#kit-day-0');
  if((await firstDay.getAttribute('open'))===null)throw Error('Current day is not open');
  await firstDay.getByLabel('What happened?').fill('Reviewed copy; did not publish yet.');
  await page.locator('#kit-day-1 summary').click();
  if(await page.locator('#kit-day-1').getByRole('button',{name:'Save check-in'}).count())throw Error('Future check-in is offered');
  for(const width of [1440,768,390]){
   await page.setViewportSize({width,height:1000});
   if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Horizontal overflow at '+width);
  }
  if(errors.length)throw Error(errors.join('\n'));
  await page.screenshot({path:root+'/tmp/marketing-copilot-mobile.png',fullPage:true});
  await page.route('https://features.test/**',route=>{
   const url=new URL(route.request().url());
   if(url.pathname.startsWith('/lightek/'))return route.fulfill({contentType:'text/css',body:fs.readFileSync(root+'/public'+url.pathname)});
   if(url.pathname.startsWith('/feature-videos/'))return route.fulfill({contentType:'video/mp4',body:fs.readFileSync(root+'/tmp/feature-showcase-sample.mp4')});
   return route.fulfill({contentType:'text/html; charset=utf-8',body:fs.readFileSync(root+'/tmp/feature-showcase-preview.html','utf8')});
  });
  await page.goto('https://features.test/features');
  await page.addStyleTag({content:'body{margin:0;background:#15121b;color:#eee7fa;font-family:system-ui,sans-serif}'});
  if(await page.locator('video').count()!==6)throw Error('The real feature page lost its video players');
  const video=page.locator('video').first();
  await video.evaluate(async element=>{element.muted=true;await element.play();});
  await page.waitForFunction(()=>document.querySelector('video').currentTime>0.2);
  const media=await video.evaluate(element=>({duration:element.duration,width:element.videoWidth,height:element.videoHeight}));
  if(media.duration<11.9||media.width!==960||media.height!==540)throw Error('The generated MP4 did not decode in the browser');
  await video.evaluate(element=>element.pause());
  for(const width of [1440,390]){
   await page.setViewportSize({width,height:1000});
   if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Feature showcase overflow at '+width);
  }
  await page.screenshot({path:root+'/tmp/feature-showcase-mobile.png',fullPage:true});
  if(errors.length)throw Error(errors.join('\n'));
  console.log('Marketing copilot and feature showcase: real ERB, typed forms, responsive layouts, current/future day guards, six video players and actual generated MP4 playback passed.');
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
