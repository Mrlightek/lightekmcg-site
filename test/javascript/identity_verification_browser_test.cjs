const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium, webkit} = require('playwright');
const root = path.resolve(__dirname, '../..');
const capture = process.env.MFA_QR_CAPTURE_DIR;
assert(capture, 'Run identity_verification_design_checks.rb with MFA_QR_CAPTURE_DIR first');
const pages = new Set(['verification.html','verification-error.html']);
const assets = {
  '/lightek/auth-verification.css': ['public/lightek/auth-verification.css','text/css'],
  '/lightek/lightek-auth-mark.svg': ['public/lightek/lightek-auth-mark.svg','image/svg+xml']
};
const server = http.createServer((req,res)=> {
  const url = new URL(req.url, 'http://fixture.local');
  res.setHeader('Cache-Control','no-store');
  if(req.method !== 'GET') { res.writeHead(405); res.end(); return; }
  if(pages.has(url.pathname.slice(1))) {
    res.setHeader('Content-Type','text/html');
    res.end(fs.readFileSync(path.join(capture,url.pathname.slice(1)))); return;
  }
  const asset = assets[url.pathname];
  if(!asset) { res.writeHead(404); res.end(); return; }
  res.setHeader('Content-Type',asset[1]); res.end(fs.readFileSync(path.join(root,asset[0])));
});
(async()=> {
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    for(const engine of [chromium,webkit]) {
      const browser = await engine.launch({headless:true});
      try {
        const context = await browser.newContext();
        await context.route('**/*',route=>route.request().url().startsWith(origin+'/') ? route.continue() : route.abort());
        const page = await context.newPage();
        for(const width of [1440,390,320]) {
          await page.setViewportSize({width,height:950});
          await page.goto(origin+'/verification.html');
          assert(await page.getByRole('heading',{name:'Confirm it’s you.',exact:true}).isVisible());
          const input = page.getByLabel('Authenticator or recovery code',{exact:true});
          await input.fill('012345');
          assert.equal(await input.inputValue(),'012345');
          await input.fill('a1b2c3d4e5f6a1b2c3d4e5f6');
          assert.equal(await input.inputValue(),'a1b2c3d4e5f6a1b2c3d4e5f6');
          assert.equal(await input.getAttribute('autocomplete'),'one-time-code');
          await page.getByText('Can’t access your authenticator?',{exact:true}).click();
          assert(await page.getByText(/Each recovery code works once/).isVisible());
          assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'verification page must fit small screens');
          const geometry = await input.evaluate(el=>({input:el.getBoundingClientRect().toJSON(),panel:el.closest('.verification-panel').getBoundingClientRect().toJSON(),size:parseFloat(getComputedStyle(el).fontSize)}));
          assert(geometry.input.left>=geometry.panel.left && geometry.input.right<=geometry.panel.right,'code field remains inside its card');
          assert(geometry.size>=16,'phone inputs stay readable without focus zoom');
          assert.equal(await page.getByRole('link',{name:'Start a new sign-in',exact:true}).getAttribute('href'),'/session/new');
          await page.goto(origin+'/verification-error.html');
          assert(await page.getByRole('alert').isVisible());
          assert.equal(await page.getByLabel('Authenticator or recovery code',{exact:true}).getAttribute('aria-invalid'),'true');
          assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        }
        await context.close();
        const noScript = await browser.newContext({javaScriptEnabled:false});
        const fallback = await noScript.newPage();
        await fallback.goto(origin+'/verification.html');
        await fallback.getByLabel('Authenticator or recovery code',{exact:true}).fill('012345');
        assert(await fallback.getByRole('button',{name:'Verify & continue',exact:true}).isEnabled());
        await noScript.close();
      } finally {await browser.close();}
    }
    console.log('IDENTITY_VERIFICATION_BROWSER_PASS: Chromium/WebKit desktop, mobile and narrow layouts; full recovery entry, errors and no-script form');
  } finally {server.close();}
})().catch(error=>{server.close();console.error(error);process.exitCode=1});
