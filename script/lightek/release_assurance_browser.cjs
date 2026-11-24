const assert = require('node:assert/strict');
const { chromium } = require('playwright');

async function main() {
  const [host, revision, screenshot] = process.argv.slice(2);
  assert.match(host, /^batch-d-[a-z0-9-]+\.staging\.[a-z0-9.-]+$/);
  assert.match(revision, /^[a-f0-9]{40}$/);
  const origin = `https://${host}`;
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.route('**/*', (route) => {
      return new URL(route.request().url()).origin === origin ? route.continue() : route.abort();
    });
    const health = await page.goto(`${origin}/__lightek/release`, { timeout: 15000 });
    assert.equal(health.url(), `${origin}/__lightek/release`);
    assert.equal(health.status(), 200);
    assert.equal((await health.json()).source_sha, revision);
    const home = await page.goto(origin, { timeout: 15000 });
    assert.equal(new URL(page.url()).origin, origin);
    assert.equal(home.status(), 200);
    assert.ok((await page.locator('body').innerText()).trim());
    await page.screenshot({ path: screenshot, timeout: 10000 });
    const signIn = await page.goto(`${origin}/sign_in`, { timeout: 15000 });
    assert.equal(new URL(page.url()).origin, origin);
    assert.equal(signIn.status(), 200);
    await page.locator('input[type=password]').waitFor({ timeout: 5000 });
  } finally {
    await browser.close();
  }
}

main().then(() => process.stdout.write('Staging HTTPS, revision, homepage and sign-in form verified\n')).catch(() => {
  process.stderr.write('Staging Chromium acceptance did not pass\n');
  process.exitCode = 1;
});
