const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');
const jsQR = require('jsqr');
const { PNG } = require('pngjs');
const root = path.resolve(__dirname, '../..');
const capture = process.env.MFA_QR_CAPTURE_DIR;
assert(capture, 'Run enterprise_form_origin_checks.rb with MFA_QR_CAPTURE_DIR first');
const html = fs.readFileSync(path.join(capture, 'enroll.html'));
const assets = new Map([
  ['/lightek/vendor/qrcode-generator/qrcode.js', ['public/lightek/vendor/qrcode-generator/qrcode.js', 'text/javascript']],
  ['/lightek/mfa-enrollment.js', ['public/lightek/mfa-enrollment.js', 'text/javascript']],
]);
const server = http.createServer((req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'same-origin');
  if (req.url === '/') { res.setHeader('Content-Type', 'text/html'); return res.end(html); }
  const asset = assets.get(req.url);
  if (!asset) { res.writeHead(404); return res.end(); }
  res.setHeader('Content-Type', asset[1]);
  res.end(fs.readFileSync(path.join(root, asset[0])));
});
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const executablePath = process.env.CHROMIUM_PATH || undefined;
  const browser = await chromium.launch({headless: true, executablePath, args: ['--no-sandbox']});
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    const external = [];
    page.on('request', request => { if (!request.url().startsWith(origin + '/')) external.push(request.url()); });
    await page.goto(origin);
    await page.waitForSelector('[data-mfa-enrollment][data-ready="true"]');
    await page.addStyleTag({path: path.join(root, 'public/lightek/people-workspace.css')});
    await page.addStyleTag({path: path.join(root, 'public/lightek/mfa-enrollment.css')});
    const expected = await page.locator('[data-mfa-enrollment]').getAttribute('data-mfa-enrollment');
    const key = await page.locator('[data-mfa-setup-key]').inputValue();
    for (const width of [1440, 390]) {
      await page.setViewportSize({width, height: 950});
      const buffer = await page.locator('[data-mfa-qr]').screenshot();
      const png = PNG.sync.read(buffer);
      const decoded = jsQR(new Uint8ClampedArray(png.data), png.width, png.height, {inversionAttempts: 'dontInvert'});
      assert(decoded, `QR did not decode at width ${width}`);
      assert.equal(decoded.data, expected);
      const uri = new URL(decoded.data);
      assert.equal(uri.protocol, 'otpauth:');
      assert.equal(uri.hostname, 'totp');
      assert.equal(uri.searchParams.get('secret'), key);
      assert.equal(uri.searchParams.get('issuer'), 'Lightek');
      assert.equal(uri.searchParams.get('digits'), '6');
      assert.equal(uri.searchParams.get('period'), '30');
      assert.equal(uri.searchParams.get('algorithm'), 'SHA1');
      assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }
    assert.equal(await page.locator('a[href^="otpauth:"]').count(), 0);
    assert.equal(await page.locator('[data-mfa-manual]').getAttribute('open'), null);
    await page.locator('[data-mfa-manual] summary').click();
    assert(await page.locator('[data-mfa-setup-key]').isVisible());
    assert.deepEqual(external, [], 'MFA setup must not contact an external QR service');
    await context.close();
    const fallback = await browser.newContext();
    await fallback.route('**/vendor/qrcode-generator/qrcode.js', route => route.abort());
    const failed = await fallback.newPage();
    await failed.goto(origin);
    await failed.waitForSelector('[data-mfa-manual][open]');
    assert.match(await failed.locator('[data-mfa-qr-status]').textContent(), /manual setup key/);
    assert.equal(await failed.locator('[data-mfa-setup-key]').inputValue(), key);
    await fallback.close();
    console.log('MFA_QR_ACCEPTANCE_PASS: real Rails enrollment QR decodes at desktop/mobile widths; local-only generation and manual fallback pass');
  } finally { await browser.close(); server.close(); }
})().catch(error => { server.close(); console.error(error); process.exitCode = 1; });
