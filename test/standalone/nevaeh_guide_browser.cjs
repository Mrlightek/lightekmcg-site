const fs=require('fs'),path=require('path'),{chromium}=require('playwright');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu']});
 try{
  const context=await browser.newContext({permissions:['clipboard-read','clipboard-write']});const page=await context.newPage();const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.route('http://127.0.0.1:18449/**',route=>{
   const url=new URL(route.request().url());const pathname=url.pathname;let file=pathname==='/dashboard/nevaeh/guide'?path.join(root,'tmp/nevaeh-guide-preview.html'):path.join(root,'public',pathname);
   if(pathname==='/dashboard/nevaeh')return route.fulfill({contentType:'text/html',body:'<h1>Editable operating input</h1>'});
   if(!fs.existsSync(file))return route.fulfill({status:404,body:'Not found'});
   return route.fulfill({contentType:pathname.endsWith('.css')?'text/css':pathname.endsWith('.js')?'application/javascript':'text/html',body:fs.readFileSync(file)});
  });
  for(const width of [1440,390]){
   await page.setViewportSize({width,height:1000});await page.goto('http://127.0.0.1:18449/dashboard/nevaeh/guide?topic=watchers');
   await page.getByRole('heading',{name:'Watch changes and respond automatically',exact:true}).waitFor();
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);if(overflow)throw Error('Guide overflow at '+width);
   if(await page.evaluate(()=>window.BAD_GUIDE))throw Error('Capability title executed HTML');
   if(!await page.locator('a[href*="capability="]').count())throw Error('No live capability reference links');
   if(!await page.locator('a[href*="software-library"]').count())throw Error('No installed manual links');
   const copy=page.locator('.ng-copy').first();await copy.click();await page.waitForFunction(()=>document.querySelector('.ng-copy').textContent==='Copied');
   if(!(await page.evaluate(()=>navigator.clipboard.readText())).includes('/watch create'))throw Error('Copy omitted runnable tutorial command');
   await page.screenshot({path:path.join(root,'tmp','nevaeh-guide-'+width+'.png'),fullPage:false});
   console.log(width+': actual Rails guide rendering, responsive layout, reference/manual links, safe titles and command copy passed');
  }
  if(errors.length)throw Error(errors.join('\n'));
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
