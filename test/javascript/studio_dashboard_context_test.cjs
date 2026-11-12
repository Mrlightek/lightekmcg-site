// Actual controller-rendered workspace and scripts; API and private engine layout are fixtures.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const {chromium} = require('playwright');
const repo = path.resolve(__dirname, '../..');
const folder = process.env.STUDIO_WORKSPACE_PREVIEW_DIR;
if (!folder) throw new Error('Export the native workspace with campaign_studio_checks.rb and STUDIO_WORKSPACE_PREVIEW_DIR first');
const context = JSON.parse(fs.readFileSync(path.join(folder, 'context.json')));
const workspace = fs.readFileSync(path.join(folder, 'workspace.html'), 'utf8');
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader']});
  try {
    const page = await browser.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://localhost:19345/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname.endsWith('/execute')) {
        const request = route.request().postDataJSON(); let result = {};
        if (request.capability === 'studio.pwa.bootstrap') result = {projects:[context.project]};
        if (request.capability.endsWith('operations.list')) result = {operations:[],publications:[]};
        if (request.capability.endsWith('assets.list')) result = {assets:[],media_presets:[],creation_recipes:[]};
        return route.fulfill({json:{status:'completed',result}});
      }
      if (url.pathname.startsWith('/lightek/')) {
        const file = path.join(repo, 'public', url.pathname);
        return route.fulfill({body:fs.readFileSync(file),contentType:file.endsWith('.css')?'text/css':'application/javascript'});
      }
      return route.fulfill({contentType:'text/html',body:`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;background:#0b0f18;color:#eee;font:14px system-ui}*{box-sizing:border-box}.dd-sidebar{position:fixed;inset:0 auto 0 0;width:220px;background:#222b3a;padding:20px}.dd-body{margin-left:220px;padding:18px}.dd-topbar{height:52px}@media(max-width:800px){.dd-sidebar{display:none}.dd-body{margin-left:0;padding:8px}}</style><aside class="dd-sidebar"><a href="/dashboard">Dashboard</a><p>Design & Content</p><p>Studio</p><p>Commerce</p></aside><div class="dd-body"><header class="dd-topbar">Dashboard / Studio</header>${workspace}</div>`});
    });
    for (const width of [1440,1024,390]) {
      await page.setViewportSize({width,height:1000});
      await page.goto(`http://localhost:19345/dashboard/studio-broadcasting/workspace/${context.scene_id}?site_id=${context.site_id}`);
      const script = page.locator('[data-studio-script]'); await script.waitFor();
      assert.match(await script.inputValue(), /Meet the makers/);
      const host = page.locator('#lightek-studio-dashboard');
      assert.equal(await host.evaluate(el => getComputedStyle(el).position), 'relative');
      assert(await host.evaluate(el => el.getBoundingClientRect().top >= 52));
      for (const link of await page.locator('.business-workspace a').all()) assert.match(await link.getAttribute('href'), new RegExp(`site_id=${context.site_id}`));
      assert.match(await page.getByRole('link',{name:'Campaign brief'}).getAttribute('href'), /\/marketing\/campaigns\/\d+\/edit\?site_id=/);
      await script.fill('Client launch script');
      await script.evaluate(el => window.originalScript = el);
      const focus = page.locator('[data-studio-focus]'); await focus.click();
      assert.equal(await focus.getAttribute('aria-pressed'), 'true');
      assert.equal(await host.evaluate(el => getComputedStyle(el).position), 'fixed');
      await page.keyboard.press('Escape');
      assert.equal(await focus.getAttribute('aria-pressed'), 'false');
      assert(await script.evaluate(el => el === window.originalScript));
      assert.equal(await script.inputValue(), 'Client launch script');
      assert.equal(await page.evaluate(() => document.documentElement.style.overflow), '');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1), `overflow at ${width}`);
      await page.screenshot({path:path.join(folder, `dashboard-studio-${width}.png`),fullPage:true});
      page.once('dialog', dialog => dialog.dismiss());
      await page.getByRole('link',{name:'Campaign brief'}).click();
      assert.equal(await script.inputValue(), 'Client launch script', 'leaving Dashboard workspaces warns before losing a draft');
      // Let the next viewport fixture navigate intentionally.
      page.once('dialog', dialog => dialog.accept());
    }
    assert.deepEqual(errors, []);
    console.log('STUDIO_CONTEXT_PASS actual workspace, site links, campaign brief, embedded/focus layout, retained drafts, leave warning at 1440/1024/390');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
