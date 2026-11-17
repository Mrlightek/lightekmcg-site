const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

// Execute the real bootstrap guard, including its initial boot and hashchange
// handler. No replacement route resolver: this caught the deployed Home bounce.
async function client(hash, { identity = true, surfaces = ['home', 'communities', 'money'] } = {}) {
  const events = {}, redirects = [];
  const payload = { identity: identity ? { user_id: 4 } : null, navigation: [], surfaces: surfaces.map(key => ({ key })) };
  const location = { hash, assign: url => redirects.push(url) };
  const ctx = {
    console: { info() {}, warn() {}, error(error) { throw error; } },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    document: { querySelector: () => null, querySelectorAll: () => [], documentElement: { setAttribute() {} } },
    window: {
      location,
      addEventListener(type, callback) { (events[type] ||= []).push(callback); },
      dispatchEvent(event) { for (const callback of events[event.type] || []) callback(event); },
      nevaeh: { bootstrap: async () => payload }
    }
  };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync('public/lightek/bootstrap-adapter.js', 'utf8'), ctx);
  await new Promise(resolve => setImmediate(resolve));
  return { ctx, location, redirects, navigate(hash) { location.hash = hash; for (const handler of events.hashchange) handler(); } };
}

for (const route of ['membership', 'membership/processing', 'membership/canceled', 'services', 'support/4', 'support/4/8', 'youtube/8']) {
  test(`${route} survives initial bootstrap and subsequent navigation`, async () => {
    const c = await client('#/' + route);
    assert.equal(c.location.hash, '#/' + route);
    assert.deepEqual(c.redirects, []);
    c.navigate('#/home');
    c.navigate('#/' + route);
    assert.equal(c.location.hash, '#/' + route);
  });
}

test('public membership and creator-support links remain available to guests', async () => {
  for (const route of ['membership', 'support/4', 'services']) {
    const c = await client('#/' + route, { identity: false });
    assert.deepEqual(c.redirects, []);
    assert.equal(c.location.hash, '#/' + route);
  }
});

test('YouTube publishing requires sign-in and preserves its return route', async () => {
  const c = await client('#/youtube/8', { identity: false });
  assert.equal(c.redirects.length, 1);
  assert.equal(c.redirects[0], '/session/new?return_to=' + encodeURIComponent('/lightek/index.html#/youtube/8'));
});

test('disabled surfaces and unknown routes remain guarded', async () => {
  const c = await client('#/support/4', { surfaces: ['communities'] });
  assert.equal(c.ctx.window.LightekStorefront.surface('home'), undefined);
  const enabled = await client('#/home');
  enabled.navigate('#/unknown');
  assert.equal(enabled.location.hash, '#/home');
});

test('existing community and money detail routes retain their configured surfaces', async () => {
  const c = await client('#/community/music');
  assert.equal(c.location.hash, '#/community/music');
  c.navigate('#/susu');
  assert.equal(c.location.hash, '#/susu');
});

test('ordinary members can render creator support and YouTube screens', async () => {
  const c = await client('#/home');
  const templates = { home: '<h1>Home</h1>', support: '<h1>Support</h1>', youtube: '<h1>YouTube</h1>' };
  c.ctx.R = Object.fromEntries(Object.entries(templates).map(([key, html]) => [key, () => html]));
  c.ctx.location = c.location;
  c.ctx.render = () => {};
  c.ctx.addEventListener = () => {};
  c.ctx.window.LightekStorefront.state.bootstrap.application = { name: 'Lightek', administration: { super_admin: false } };
  c.ctx.window.LightekStorefront.state.surfaces.set('home', { key: 'home' });
  c.ctx.document.getElementById = () => ({ innerHTML: '' });
  // Minimal DOM template boundary: the policy wrapper still executes in full.
  c.ctx.document.createElement = () => ({ content: { querySelector: () => null }, innerHTML: '' });
  vm.runInContext(fs.readFileSync('public/lightek/application-settings.js', 'utf8'), c.ctx);
  assert.match(c.ctx.R.support(), /Support/);
  assert.match(c.ctx.R.youtube(), /YouTube/);
  c.ctx.window.LightekStorefront.state.surfaces.delete('home');
  assert.match(c.ctx.R.support(), /administrator has disabled/);
  assert.match(c.ctx.R.youtube(), /administrator has disabled/);
});
