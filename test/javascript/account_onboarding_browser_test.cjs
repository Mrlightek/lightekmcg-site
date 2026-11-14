// Actual Rails-rendered first-use/settings/recovery pages; fixture codes only.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium, webkit } = require('playwright');
const root = path.resolve(__dirname, '../..');
const capture = process.env.MFA_QR_CAPTURE_DIR;
assert(capture, 'Run enterprise_onboarding_checks.rb with MFA_QR_CAPTURE_DIR first');
const pages = new Set(['client-home.html', 'client-settings.html', 'password-setup.html', 'recovery.html']);
const assets = new Map([
  ['/lightek/mfa-recovery.js', ['public/lightek/mfa-recovery.js', 'text/javascript']],
  ['/lightek/people-workspace.css', ['public/lightek/people-workspace.css', 'text/css']],
]);
const server = http.createServer((req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'same-origin');
  const file = req.url.slice(1);
  if (pages.has(file)) {
    res.setHeader('Content-Type', 'text/html');
    return res.end(fs.readFileSync(path.join(capture, file)));
  }
  const asset = assets.get(req.url);
  if (!asset) { res.writeHead(404); return res.end(); }
  res.setHeader('Content-Type', asset[1]);
  res.end(fs.readFileSync(path.join(root, asset[0])));
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const engine of [chromium, webkit]) {
      const browser = await engine.launch({headless: true});
      try {
        const context = await browser.newContext({acceptDownloads: true});
        // Fixtures never submit to an application or load external providers.
        await context.route('**/*', route => route.request().url().startsWith(origin + '/') ? route.continue() : route.abort());
        const page = await context.newPage();
        for (const width of [1440, 390]) {
          await page.setViewportSize({width, height: 950});
          await page.goto(`${origin}/client-home.html`);
          assert.equal(await page.getByRole('heading', {name: 'Your workspace', exact: true}).count(), 1);
          assert.equal(await page.getByRole('link', {name: 'All my applications'}).count(), 1);
          await page.goto(`${origin}/client-settings.html`);
          assert.equal(await page.getByRole('link', {name: /^Sign-in security/}).getAttribute('href'), '/identity/security');
          assert.equal(await page.getByText('Compute providers', {exact: true}).count(), 0);
          assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
          await page.goto(`${origin}/password-setup.html`);
          for (const name of ['password', 'password_confirmation']) {
            const input = page.locator(`input[name="${name}"]`);
            assert.equal(await input.getAttribute('type'), 'password');
            await input.fill('fixture-only-not-a-real-password');
            assert.equal(await input.evaluate(el => el.type), 'password');
            assert.equal(await input.evaluate(el => getComputedStyle(el).getPropertyValue('-webkit-text-security')), 'disc');
          }
        }
        const external = [];
        page.on('request', request => { if (!request.url().startsWith(origin + '/')) external.push(request.url()); });
        await page.goto(`${origin}/recovery.html`);
        const codes = await page.locator('[data-mfa-recovery-codes] code').allTextContents();
        assert.equal(codes.length, 10);
        assert.equal(new Set(codes).size, 10);
        const button = page.getByRole('button', {name: 'Download recovery codes (.txt)', exact: true});
        for (let attempt = 0; attempt < 2; attempt++) {
          const downloadEvent = page.waitForEvent('download');
          await button.click();
          const download = await downloadEvent;
          assert.equal(download.suggestedFilename(), 'lightek-recovery-codes.txt');
          const text = fs.readFileSync(await download.path(), 'utf8');
          for (const code of codes) assert.equal(text.split('\n').filter(line => line === code).length, 1);
          assert.match(text, /Each code can be used once/);
          assert.equal(await page.locator('a[download]').count(), 0);
        }
        assert.deepEqual(external, [], 'Recovery download must remain local to the browser');
        assert.equal(await page.evaluate(() => localStorage.length + sessionStorage.length), 0);
        await page.evaluate(() => { URL.createObjectURL = () => { throw new Error('Fixture download failure'); }; });
        await button.click();
        assert.match(await page.locator('[data-mfa-recovery-status]').textContent(), /Copy the codes above/);
        assert.equal(await page.locator('[data-mfa-recovery-codes] code').count(), 10);
        await context.close();
        const noScript = await browser.newContext({javaScriptEnabled: false});
        const fallback = await noScript.newPage();
        await fallback.goto(`${origin}/recovery.html`);
        assert.equal(await fallback.locator('[data-mfa-recovery-codes] code').count(), 10);
        assert.equal(await fallback.locator('[data-mfa-recovery-download]').isVisible(), false);
        await noScript.close();
      } finally { await browser.close(); }
    }
    console.log('ACCOUNT_ONBOARDING_BROWSER_PASS: Chromium/WebKit desktop/mobile settings, masked setup fields, exact local recovery downloads and copy fallback');
  } finally { server.close(); }
})().catch(error => { server.close(); console.error(error); process.exitCode = 1; });
