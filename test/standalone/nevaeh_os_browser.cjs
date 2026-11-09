const fs = require('fs'), path = require('path'), {chromium} = require('playwright');
const root = path.resolve(__dirname, '../..');
(async () => {
  fs.mkdirSync(path.join(root, 'tmp'), {recursive: true});
  const browser = await chromium.launch({headless: true, ...(process.env.CHROMIUM_PATH ? {executablePath: process.env.CHROMIUM_PATH} : {}), args: ['--no-sandbox', '--no-zygote', '--single-process', '--disable-gpu']});
  try {
    const page = await browser.newPage(), errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://127.0.0.1:18449/**', async route => {
      const request = route.request(), pathname = new URL(request.url()).pathname;
      let contentType = 'application/json', body = '{}';
      if (pathname === '/dashboard/nevaeh') {
        contentType = 'text/html';
        body = fs.readFileSync(path.join(root, 'app/views/dashboard/nevaeh_os/index.html.erb'), 'utf8').replace('<%= csrf_meta_tags %>', '<meta name="csrf-token" content="test-token">');
      } else if (['/nevaeh/os.js', '/nevaeh/os.css'].includes(pathname)) {
        contentType = pathname.endsWith('.js') ? 'application/javascript' : 'text/css';
        body = fs.readFileSync(path.join(root, 'public', pathname), 'utf8');
      } else if (pathname.endsWith('/state')) {
        body = JSON.stringify({user: {id: 1}, host_control: true, resources: [], agents: [{id: 2, name: 'Sage', role: 'Strategist', system_key: 'sage', autonomy: 'scheduled', enabled: true}],
          agent_workers: [{id: 8, agent_id: 2, agent: 'Sage', name: 'Susu monitor', enabled: true, interval_minutes: 60, last_status: 'completed'}],
          memory: {categories: {Conversations: false, 'Goals & projects': false, 'Birth data': false, Preferences: false, 'Faith practices': false}, items: []}, actions: [], kernel: {chart_accuracy: 'illustrative'}});
      } else if (pathname.endsWith('/ask')) {
        const q = request.postDataJSON().q;
        if (request.headers()['x-csrf-token'] !== 'test-token') throw Error('Missing CSRF token');
        body = JSON.stringify({text: q === 'susu.list' ? 'Your Susus are being retrieved.' : 'Grounded test response <img src=x onerror=alert(1)>', status: q === 'susu.list' ? 'pending' : 'ready',
          action_id: q === 'susu.list' ? 42 : null, influences: [{planet: 2, reason: 'Intent: capability · susu.list'}, {planet: 6, reason: 'Permissions use your signed-in account and are checked again when work executes.'}], sources: [], memory: null});
      } else if (pathname.endsWith('/actions/42')) {
        body = JSON.stringify({id: 42, status: 'completed', result: {work_item_id: 71}, downstream: {id: 71, status: 'done', result: {groups: [{id: 9, name: 'Community fund', status: 'active'}]}}});
      }
      return route.fulfill({contentType, body});
    });
    for (const [width, height] of [[1600, 1000], [1280, 800], [1100, 900], [390, 844]]) {
      await page.setViewportSize({width, height});
      await page.goto('http://127.0.0.1:18449/dashboard/nevaeh');
      await page.waitForFunction(() => document.querySelector('.chips span').textContent.includes('Connected'));
      await page.locator('#q').fill('/help <svg onload=alert(1)>');
      await page.locator('#f').evaluate(form => form.requestSubmit());
      await page.waitForFunction(() => document.querySelector('#at').textContent.includes('Grounded test'));
      if (await page.locator('#at img').count() || await page.locator('#trail svg').count()) throw Error('HTML injection');
      if (width > 1000) {
        const evidence = await page.locator('.evidence-row p').last().boundingBox();
        if (evidence.width < 180) throw Error('Evidence text compressed into icon column: ' + evidence.width);
      }
      await page.locator('#q').fill('susu.list');
      await page.locator('#f').evaluate(form => form.requestSubmit());
      await page.waitForFunction(() => document.querySelector('#receipt').textContent.includes('Community fund'));
      if (!await page.locator('#receipt .result-card').count()) throw Error('Susu result card absent');
      const bounds = await page.locator('#q').boundingBox();
      if (!bounds || bounds.y < 0 || bounds.y + bounds.height > height) throw Error('Command input obscured');
      const layout = await page.evaluate(() => ({width: document.documentElement.scrollWidth, viewport: innerWidth}));
      if (layout.width > width) throw Error('Horizontal overflow ' + JSON.stringify(layout));
      if (width === 390) {
        await page.locator('#ta').click();
        await page.waitForFunction(() => document.querySelector('.panel').classList.contains('open'));
        if (!await page.locator('#agent-jobs').textContent().then(text => text.includes('Sage'))) throw Error('Agent workforce missing');
        await page.keyboard.press('Escape');
        await page.waitForFunction(() => !document.querySelector('.panel').classList.contains('open'));
      }
      await page.waitForFunction(() => document.querySelector('#boot').classList.contains('off'));
      await page.waitForTimeout(1100);
      await page.screenshot({path: path.join(root, 'tmp', `nevaeh-os-${width}.png`)});
      console.log(`${width}x${height}: evidence width, result cards, escaping, input visibility, workforce and layout passed`);
    }
    await page.emulateMedia({reducedMotion: 'reduce'});
    await page.reload();
    await page.waitForFunction(() => document.querySelector('#boot').classList.contains('off'));
    if (errors.length) throw Error(errors.join('\n'));
    console.log('Reduced motion and zero browser exceptions passed');
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
