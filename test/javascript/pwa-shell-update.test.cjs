const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('public/lightek/sw.js', 'utf8');

function install(fail = false) {
  const handlers = {}, requests = [];
  let activated = false, pending;
  vm.runInNewContext(source, {
    Request: class { constructor(url, options) {this.url=url; this.cache=options.cache;} },
    caches: {open: async () => ({addAll: async list => {
      requests.push(...list);
      if (fail) throw new Error('asset unavailable');
    }})},
    self: {addEventListener: (event, handler) => handlers[event]=handler,
      skipWaiting: async () => {activated=true;}}
  });
  handlers.install({waitUntil: promise => pending=promise});
  return {requests, pending, activated: () => activated};
}

test('a new shell fetches every asset freshly, including versioned route guards', async () => {
  const run = install();
  await run.pending;
  assert.ok(run.requests.length > 50);
  assert.ok(run.requests.every(request => request.cache === 'reload'));
  const html = fs.readFileSync('public/lightek/index.html', 'utf8');
  for (const name of ['bootstrap-adapter', 'application-settings']) {
    const path = run.requests.find(request => request.url.includes('/'+name+'.js')).url;
    assert.ok(path.includes('?v='));
    assert.ok(html.includes('src="'+path+'"'));
  }
  assert.equal(run.activated(), true);
});

test('an incomplete install never replaces the working offline shell', async () => {
  const run = install(true);
  await assert.rejects(run.pending, /asset unavailable/);
  assert.equal(run.activated(), false);
});
