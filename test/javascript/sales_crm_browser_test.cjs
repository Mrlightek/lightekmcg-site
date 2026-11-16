// Native controller-rendered views; only the private engine shell is a fixture.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { chromium } = require('playwright');
const repo = path.resolve(__dirname, '../..'), folder = process.env.SALES_PREVIEW_DIR;
if (!folder) throw new Error('Export views with SALES_PREVIEW_DIR and campaign_performance_checks.rb plus website_audit_checks.rb first');
(async () => {
  const browser = await chromium.launch({ headless: true, ignoreDefaultArgs: ['--enable-features=CDPScreenshotNewSurface'], executablePath: process.env.CHROMIUM_PATH || undefined, args: ['--no-sandbox', '--no-zygote', '--single-process', '--disable-gpu'] });
  try {
    const page = await browser.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://sales.test/**', async route => {
      const url = new URL(route.request().url());
      if (url.pathname.startsWith('/lightek/')) return route.fulfill({ body: fs.readFileSync(path.join(repo, 'public', url.pathname)), contentType: 'text/css' });
      const tab = url.pathname.slice(1) || 'today';
      const html = fs.readFileSync(path.join(folder, `${tab}.html`), 'utf8');
      return route.fulfill({ contentType: 'text/html', body: `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>body{margin:0;background:#0c1019;color:#e7edf8;font:14px system-ui}.shell{padding:24px 32px;margin-left:210px}.sidebar{position:fixed;width:170px;padding:20px;inset:0 auto 0 0;background:#131a26;border-right:1px solid #30394b}.sidebar strong{letter-spacing:.15em}.sidebar p{color:#a4afc4;font-size:13px}.topbar{padding-bottom:24px;color:#a4afc4;font-size:12px}@media(max-width:800px){.sidebar{display:none}.shell{margin:0;padding:16px}}</style></head><body><aside class="sidebar"><strong>LIGHTEK</strong><p>Business</p><p>Sales & CRM</p><p>Design & Content</p><p>Studio</p><p>Commerce</p></aside><div class="shell"><div class="topbar">Dashboard / Sales & CRM</div>${html}</div></body></html>` });
    });
    for (const width of [1440, 1024, 390]) {
      await page.setViewportSize({ width, height: 1000 });
      for (const screen of ['today', 'pipeline', 'deal', 'intake', 'inquiry', 'tasks', 'quote', 'lifecycle', 'growth', 'growth-plan', 'campaign-content', 'publishing', 'website-audit', 'performance']) {
        await page.goto(`http://sales.test/${screen}`);
        await page.getByRole('heading', { name: screen === 'performance' ? 'Campaign performance' : screen === 'website-audit' ? 'Website growth audit' : screen === 'lifecycle' ? 'Onboarding & offboarding' : screen.startsWith('growth') ? 'Growth & attribution' : screen === 'campaign-content' ? 'Campaign content & review' : screen === 'publishing' ? 'Publishing calendar' : 'Sales & CRM', exact: true }).waitFor();
        if (screen === 'performance') await page.locator('.growth-performance-setup').evaluate(node => { node.open = true; });
        assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), `page overflow ${screen} at ${width}`);
        for (const input of await page.locator('.sales-form input:not([type=hidden]), .sales-form select, .sales-form textarea').all()) {
          const box = await input.boundingBox();
          assert(box && box.x >= 0 && box.x + box.width <= width + 1, `form outside viewport ${width}`);
        }
        if (screen === 'performance') {
          assert(await page.getByRole('heading', { name: 'Observed results' }).isVisible());
          assert.equal(await page.getByRole('textbox', { name: /^Tracking URL for/ }).count(), 2);
          assert(await page.getByRole('button', { name: 'Prepare editable follow-up' }).isVisible());
          assert(await page.getByRole('button', { name: 'Pin versions and create placement links' }).isVisible());
          await page.getByText('Pinned version and placement', { exact: true }).first().evaluate(node => node.click());
          assert(await page.locator('.growth-performance-arm details').first().evaluate(node => node.open));
          assert(await page.getByRole('navigation', { name: 'Performance review history' }).isVisible());
        }
        if (screen === 'website-audit') {
          assert(await page.getByRole('button', { name: 'Run native website audit' }).isVisible());
          assert(await page.getByRole('heading', { name: 'Review changes and recovery' }).isVisible());
          assert(await page.getByText('verified_absent', { exact: false }).isVisible());
          assert(await page.getByRole('button', { name: 'Roll back saved change & recheck' }).isVisible());
          await page.getByText('Evidence and source', { exact: true }).first().evaluate(node => node.click());
          assert(await page.locator('.growth-audit-finding details').first().evaluate(node => node.open));
        }
        if (screen === 'publishing') {
          assert(await page.getByRole('heading', { name: 'Release agenda', exact: true }).isVisible());
          assert(await page.getByRole('button', { name: 'Schedule this reviewed version' }).isVisible());
          assert(await page.getByLabel('Time zone', { exact: true }).isVisible());
          assert(await page.getByText('published-reference', { exact: false }).isVisible());
        }
        if (screen === 'campaign-content') {
          assert(await page.getByRole('button', { name: 'Prepare content variations' }).isVisible());
          assert.equal(await page.getByRole('button', { name: 'Approve & use this version' }).count(), 2);
          assert(await page.getByText('This saved version is immutable.', { exact: false }).isVisible());
          assert(await page.getByRole('link', { name: 'Open campaign editor / Studio' }).isVisible());
        }
        if (screen === 'growth-plan') {
          assert(await page.getByRole('heading', { name: 'Daily growth plan', exact: true }).isVisible());
          assert(await page.getByRole('button', { name: 'Refresh today’s plan' }).isVisible());
          assert(await page.getByText('Draft creation recorded', { exact: false }).isVisible());
          await page.getByText('Why Nevaeh recommended this', { exact: true }).first().evaluate(node => node.click());
          assert(await page.locator('.growth-plan-evidence').first().evaluate(node => node.open));
          assert(await page.getByRole('navigation', { name: 'Recent growth plans' }).isVisible());
        }
        if (screen === 'growth') {
          assert.equal(await page.locator('.growth-funnel li').count(), 7);
          assert(await page.getByRole('button', { name: 'Save business brief' }).isVisible());
          assert(await page.getByRole('button', { name: 'Create tracking link' }).isVisible());
          const share = page.getByRole('textbox', { name: 'Tracking URL for Instagram profile' });
          assert(await share.getAttribute('readonly') !== null);
          assert((await share.inputValue()).startsWith('https://lightek.test/g/'));
        }
        if (screen === 'deal') {
          await page.getByLabel('Next step', { exact: true }).fill('Confirm budget and decision maker');
          await page.getByLabel(/^Deal value/).fill('1250.55');
          assert.equal(await page.getByLabel(/^Deal value/).inputValue(), '1250.55');
          assert(await page.getByRole('button', { name: 'Save deal' }).isVisible());
          assert(await page.getByRole('link', { name: 'North Studio', exact: true }).isVisible());
        }
        if (process.env.SALES_SCREENSHOTS === '1') await page.screenshot({ timeout: 10000, path: path.join(folder, `${screen}-${width}.png`), fullPage: true });
      }
    }
    assert.deepEqual(errors, []);
    console.log('SALES_BROWSER_PASS native Today, pipeline, deal, inquiry inbox/review, tasks, quotes, lifecycle, Growth, daily-plan campaign-content publishing-calendar and website-audit and campaign-performance views; currency inputs, relationship links and responsive layout at 1440/1024/390');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
