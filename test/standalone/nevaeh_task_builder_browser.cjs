// Render the real ERB fixture first: ruby test/standalone/nevaeh_task_builder_checks.rb
const {chromium}=require('playwright'),fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'../..');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox']});
 try {
  const page=await browser.newPage({viewport:{width:1440,height:1000}}),errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.route('https://builder.test/**',route=>{
   const pathname=new URL(route.request().url()).pathname;
   if(pathname.startsWith('/lightek/'))return route.fulfill({contentType:pathname.endsWith('.js')?'application/javascript':'text/css',body:fs.readFileSync(root+'/public'+pathname)});
   return route.fulfill({contentType:'text/html',body:fs.readFileSync(root+'/tmp/nevaeh-task-builder-preview.html','utf8')+'<script src="/lightek/nevaeh/task-builder.js"></script>'});
  });
  await page.goto('https://builder.test/employee/nevaeh/factory?tab=tasks');
  const form=page.locator('[data-task-builder]'),fixedSite=form.locator('[data-builder-fixed="site_id"]'),expectedSite=form.locator('[data-builder-expected="site_id"] input');
  if(await expectedSite.isEnabled())throw Error('Fixed site incorrectly requires an expected variable value');
  if(!await form.locator('[data-builder-expected="title"] input').isVisible())throw Error('Variable expected title is hidden');
  await fixedSite.fill('');
  if(!await expectedSite.isVisible()||(await expectedSite.getAttribute('required'))===null)throw Error('Variable site did not request an expected value');
  await expectedSite.fill('77');await fixedSite.fill('12');
  const values=await form.evaluate(element=>Object.fromEntries(new FormData(element)));
  if(values['extension[fixed][site_id]']!=='12'||'extension[expected][site_id]' in values)throw Error('Form serialized a fixed input as a variable');
  if(values['extension[expected][title]']!=='About us')throw Error('Independent expectation was lost');
  if(await page.locator('script').evaluateAll(nodes=>nodes.some(node=>node.textContent.includes('window.BAD'))))throw Error('Task name injected executable HTML');
  await page.getByText('Action, source and test evidence',{exact:true}).click();
  await page.getByText('Action, source and test evidence',{exact:true}).click();
  for(const width of [1440,390]){
   await page.setViewportSize({width,height:1000});
   if(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))throw Error('Horizontal overflow at '+width);
  }
  if(errors.length)throw Error(errors.join('\n'));
  await page.screenshot({path:root+'/tmp/nevaeh-task-builder-mobile.png',fullPage:true});
  console.log('Task builder: real ERB, typed form serialization, safe text, details and desktop/mobile layout passed.');
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
