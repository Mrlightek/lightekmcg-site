const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { chromium, webkit } = require('playwright');

const css = readFileSync('public/lightek/guided-tour.css', 'utf8');
const script = readFileSync('public/lightek/guided-tour.js', 'utf8');
const previewScript = readFileSync('public/lightek/agency-demo-preview.js', 'utf8');
const step = (scope, title) => `data-tour-step="${scope}" data-tour-title="${title}" data-tour-body="About ${title}."`;
const fixture = (route) => {
  const scope = route === 'pwa' ? 'pwa' : 'dashboard';
  const demo = route.startsWith('demo');
  const webDesign = route === 'demo-web';
  const marketing = route === 'demo-marketing';
  const business = route === 'business';
  return `<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    *{box-sizing:border-box}body{font:15px system-ui;background:#f7f8fa;color:#182537;margin:16px}
    header{position:sticky;top:0;background:white;padding:6px;display:flex;align-items:center;gap:16px}
    section{margin:24px 0} #menu{display:none}
    @media(max-width:650px){#tool-search{display:none} #menu{display:block}}
    ${css}
  </style>
  <body data-tour-app="${scope}" data-tour-account="${route === 'other' ? 9 : 8}">
  <header>
    <button type="button" data-tour-open class="lightek-tour-trigger" hidden>Take a tour</button>
    <button type="button" id="menu">Menu</button>
    <label id="tool-search" ${step(scope, 'Find a tool')} data-tour-fallback="#menu">Search <input type="search"></label>
    <button type="button" ${step(scope, 'Open settings')}>Settings</button>
  </header>
  ${demo ? `<main data-tour-page="agency-demo" data-tour-auto data-tour-variant="${webDesign ? 'web_design' : marketing ? 'marketing' : 'general'}">
    <h1 ${step('agency-demo', 'Your agency demo')}>Demo</h1>
    <section ${step('agency-demo', 'Name your agency')} data-tour-try><label>Agency name <input name="brand_name"></label></section>
    <section hidden ${step('agency-demo', 'Unavailable feature')}>Hidden features</section>
    ${webDesign ? `<section data-agency-preview><div ${step('agency-demo', 'Edit a page section')} data-tour-try>
      <label>Hero headline <input data-demo-input="headline" value="Sample headline"></label>
      <output data-demo-output="headline">Sample headline</output></div></section>` : ''}
    ${marketing ? `<section data-agency-preview><div ${step('agency-demo', 'Find a prospect')} data-tour-try>
      <label>Practice search <select data-demo-input="prospect"><option>Bakery</option><option>Salon</option></select></label>
      <output data-demo-output="prospect">Bakery</output></div></section>` : ''}
    <div style="min-height:830px"></div>
    <button type="button" ${step('agency-demo', 'Activate your agency when ready')} onclick="window.checkoutStarted = true">Upgrade</button>
  </main>` : ''}
  ${business ? `<main data-tour-page="business"><h1 ${step('business', 'Choose the website')}>Business</h1></main>` : ''}
  <script>${script}</script><script>${previewScript}</script></body>`;
};

async function assertPosition(page) {
  const rect = await page.locator('dialog').boundingBox();
  assert(rect.x >= 0 && rect.y >= 0);
  assert(rect.x + rect.width <= page.viewportSize().width);
  assert(rect.y + rect.height <= page.viewportSize().height);
}

async function exercise(engine) {
  const browser = await engine.launch({ headless: true });
  try {
    for (const width of [390, 1200]) {
      const page = await browser.newPage({ viewport: { width, height: 720 } });
      await page.route('http://lightek-tour.test/*', route => route.fulfill({
        contentType: 'text/html',
        body: fixture(new URL(route.request().url()).pathname.slice(1))
      }));
      const visit = name => page.goto(`http://lightek-tour.test/${name}`);
      const dialog = page.getByRole('dialog');
      const heading = dialog.getByRole('heading');
      await visit('demo');
      await heading.waitFor();
      assert.equal(await heading.textContent(), 'Your agency demo');
      assert.equal(await dialog.locator('[data-tour-count]').textContent(), '1 of 3');
      await dialog.getByRole('button', { name: 'Next' }).click();
      await dialog.getByRole('button', { name: 'Try it' }).click();
      await dialog.waitFor({ state: 'hidden' });
      assert.equal(await page.evaluate(() => document.activeElement.name), 'brand_name');
      await page.getByRole('textbox', { name: 'Agency name' }).fill('Northside');
      await page.reload();
      await page.getByRole('button', { name: 'Resume tour' }).click();
      assert.equal(await heading.textContent(), 'Name your agency');
      await dialog.getByRole('button', { name: 'Back' }).click();
      assert.equal(await heading.textContent(), 'Your agency demo');
      await dialog.getByRole('button', { name: 'Next' }).click();
      await dialog.getByRole('button', { name: 'Next' }).click();
      assert.equal(await heading.textContent(), 'Activate your agency when ready');
      await assertPosition(page);
      assert.equal(await page.evaluate(() => Boolean(window.checkoutStarted)), false);
      await dialog.getByRole('button', { name: 'Finish' }).click();
      await page.reload();
      assert.equal(await dialog.count(), 0);
      await page.getByRole('button', { name: 'Take a tour' }).click();
      await page.keyboard.press('Escape');
      await dialog.waitFor({ state: 'hidden' });
      assert.equal(await page.evaluate(() => document.activeElement.textContent), 'Take a tour');

      await visit('demo-web');
      await heading.waitFor();
      assert.equal(await dialog.locator('[data-tour-count]').textContent(), '1 of 4');
      await dialog.getByRole('button', { name: 'Next' }).click();
      await dialog.getByRole('button', { name: 'Next' }).click();
      assert.equal(await heading.textContent(), 'Edit a page section');
      await dialog.getByRole('button', { name: 'Try it' }).click();
      await page.getByRole('textbox', { name: 'Hero headline' }).fill('Open for business');
      assert.equal(await page.locator('[data-demo-output="headline"]').textContent(), 'Open for business');

      await visit('demo-marketing');
      await heading.waitFor();
      await dialog.getByRole('button', { name: 'Next' }).click();
      await dialog.getByRole('button', { name: 'Next' }).click();
      assert.equal(await heading.textContent(), 'Find a prospect');
      await dialog.getByRole('button', { name: 'Try it' }).click();
      await page.getByRole('combobox', { name: 'Practice search' }).selectOption('Salon');
      assert.equal(await page.locator('[data-demo-output="prospect"]').textContent(), 'Salon');

      await visit('dashboard');
      await heading.waitFor();
      assert.equal(await heading.textContent(), 'Find a tool');
      assert.equal(await dialog.locator('[data-tour-spotlight]').evaluate(node => node.hidden), false);
      await dialog.getByRole('button', { name: 'Skip tour' }).click();
      await visit('business');
      assert.equal(await dialog.count(), 0);
      await page.getByRole('button', { name: 'Take a tour' }).click();
      assert.equal(await heading.textContent(), 'Choose the website');
      await page.evaluate(() => document.dispatchEvent(new Event('turbo:before-cache')));
      assert.equal(await dialog.count(), 0);
      await visit('other');
      await heading.waitFor();
      assert.equal(await heading.textContent(), 'Find a tool');

      await visit('pwa');
      assert.equal(await dialog.count(), 0);
      await page.evaluate(() => {
        window.LightekIdentity = { id: 8, authenticated: true };
        window.dispatchEvent(new Event('lightek.bootstrap.ready'));
      });
      await heading.waitFor();
      await assertPosition(page);
      await page.close();
    }
  } finally { await browser.close(); }
}

(async () => {
  for (const engine of process.env.TOUR_CHROMIUM_ONLY ? [chromium] : [chromium, webkit]) await exercise(engine);
  console.log('Guided tours passed on mobile and desktop');
})().catch(error => { console.error(error); process.exitCode = 1; });
