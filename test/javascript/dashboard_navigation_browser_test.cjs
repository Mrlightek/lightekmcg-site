const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium, webkit} = require('playwright');
const root = path.resolve(__dirname, '../..');
const css = fs.readFileSync(path.join(root, 'public/lightek/dashboard.css'), 'utf8');
const script = fs.readFileSync(path.join(root, 'public/lightek/dashboard.js'), 'utf8');
const fixture = dark => `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
*{box-sizing:border-box}body{margin:0;font:14px system-ui;--dd-border:${dark?'#455269':'#dce2eb'};--dd-text-primary:${dark?'#edf1f7':'#172033'};--dd-text-secondary:${dark?'#aebacc':'#596579'};--dd-sidebar-bg:${dark?'#181f2a':'#fff'};--dd-accent:${dark?'#8cb4ff':'#2563eb'};background:var(--dd-sidebar-bg);color:var(--dd-text-primary)}
.dd-sidebar{width:260px;max-width:100%}.dd-nav-item{display:flex;padding:8px;color:inherit}.dd-nav-label{display:flex;align-items:center;cursor:pointer}.dd-nav{padding:8px}.dd-content{max-width:1100px}${css}</style>
<body class="dd-dashboard"><aside class="dd-sidebar"><nav class="dd-nav"><div data-navigation-search hidden class="dd-nav-search"><label for="search">Find a tool</label><input type="search" id="search" data-tool-search></div>
<details class="dd-nav-group" data-tool-group open><summary class="dd-nav-label">Start</summary><a href="#home" data-tool-link class="dd-nav-item">Home</a></details>
<details class="dd-nav-group" data-tool-group><summary class="dd-nav-label">Business & money</summary><a href="#orders" data-tool-link class="dd-nav-item">Manage orders</a><a href="#sales" data-tool-link class="dd-nav-item">Sales</a></details>
<details class="dd-nav-group" data-tool-group><summary class="dd-nav-label">Create & publish</summary><a href="#studio" data-tool-link class="dd-nav-item">Studio</a></details><p data-tool-empty role="status" hidden>No matching tools.</p></nav></aside>
<main class="dd-content"><h1>What would you like to do?</h1><section class="dd-task-grid">${['Run my business','Update my website','Create a video or image','Manage my clients'].map(label=>`<a class="dd-task-card" href="#task"><strong>${label}</strong><span>Choose a task to get started.</span></a>`).join('')}</section><details class="dd-more-tools"><summary>More business tools</summary><a href="#marketing">Marketing</a></details></main></body>`;
(async()=>{
 for(const engine of [chromium,webkit]) {
  const browser = await engine.launch({headless:true, ...(engine===chromium && process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH}: {})});
  try {
   for(const width of [390,1440]) for(const dark of [false,true]) {
    const page=await browser.newPage({viewport:{width,height:1000}});
    await page.setContent(fixture(dark));
    // Native groups remain usable before enhancement.
    await page.getByText('Business & money',{exact:true}).click();
    assert(await page.getByText('Manage orders',{exact:true}).isVisible());
    await page.getByText('Business & money',{exact:true}).click();
    await page.addScriptTag({content:script});
    const search=page.getByLabel('Find a tool');
    await search.fill('  STUDIO  ');
    assert(await page.getByText('Studio',{exact:true}).isVisible());
    assert(!(await page.getByText('Manage orders',{exact:true}).isVisible()));
    await search.fill('zz-no-match');
    assert(await page.locator('[data-tool-empty]').isVisible());
    await search.press('Escape');
    assert.equal(await search.inputValue(),'');
    assert.deepEqual(await page.locator('[data-tool-group]').evaluateAll(gs=>gs.map(g=>g.open)),[true,false,false]);
    await search.fill('orders');
    await search.press('Tab');
    assert.equal(await page.evaluate(()=>document.activeElement.tagName),'SUMMARY');
    await page.evaluate(()=>document.dispatchEvent(new Event('turbo:before-cache')));
    await page.evaluate(()=>document.dispatchEvent(new Event('turbo:load')));
    await search.fill('studio');
    assert(await page.getByText('Studio',{exact:true}).isVisible());
    await search.fill('');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    if(process.env.UX_SCREENSHOT && width===1440 && dark===true && engine===chromium) await page.screenshot({path:process.env.UX_SCREENSHOT,fullPage:true});
    await page.close();
   }
  } finally {await browser.close();}
 }
 console.log('Navigation: search, keyboard, no-JS disclosure, Turbo restore, light/dark and mobile/desktop passed in Chromium/WebKit');
})().catch(error=>{console.error(error);process.exitCode=1});
