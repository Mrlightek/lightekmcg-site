const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');

const root = path.resolve(__dirname, '../../public/lightek');
const source = name => fs.readFileSync(path.join(root, name), 'utf8');

async function until(condition) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('Studio preview did not update');
}

async function check(dashboard) {
  const host = dashboard ? '<div data-unified-studio data-site-id="2" data-scene-id="7"></div>' : '<div id="app"></div>';
  const dom = new JSDOM(host, { url: 'https://studio.example/#/studio/7', runScripts: 'outside-only', pretendToBeVisual: true });
  const { window } = dom;
  const scene = { id: 7, name: 'Pilot', settings: {}, lock_version: 1 };
  const project = { id: 3, name: 'Production', unassigned_scenes: [scene] };
  const requests = [];
  window.nevaeh = { execute: async ({ capability, payload }) => {
    switch (capability) {
      case 'studio.pwa.bootstrap': return { result: { projects: [project] } };
      case 'studio.workspace.assets.list': return { result: { assets: [] } };
      case 'studio.workspace.operations.list': return { result: { operations: [] } };
      case 'studio.workspace.character.scene.status': return { result: { status: 'idle' } };
      case 'studio.workspace.character.scene.prepare': {
        requests.push(payload);
        const seconds = Number(payload.fountain.match(/CLOSE @ (\d+)/)[1]);
        return { result: { status: 'completed', operation_id: 80, scene_id: 9, cast_asset_id: 10, url: '/preview.mp4',
          inputs: { script_preview: { speaker: 'ALEX', cuts: [{ camera: 'close', seconds }] } } } };
      }
      default: throw Error(capability);
    }
  } };
  if (dashboard) {
    window.fetch = async (_url, options) => ({ status: 'completed', ...await window.nevaeh.execute(JSON.parse(options.body)) });
    window.nevaeh.parseResponse = async response => response;
  }

  try {
    window.eval(source('studio-unified.js'));
    if (!dashboard) window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'), '7');
    const scriptLink = () => Array.from(window.document.querySelectorAll('a')).find(link => link.textContent === 'Script & preview');
    await until(scriptLink);
    const url = new URL(scriptLink().href);
    if (dashboard) {
      assert.equal(url.pathname, '/dashboard/studio-broadcasting/workspace/7');
      assert.equal(url.searchParams.get('workspace'), 'script');
    } else {
      assert.equal(url.hash, '#/studio/7/script');
      window.location.hash = url.hash;
      assert.equal(window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'), '7'), false);
      window.LightekUnifiedStudio.leave();
    }

    // Exercise the shared Script editor with the transport and shell state supplied by each host.
    window.app = window.document.body;
    window.A = {};
    window.R = {};
    window.E = value => String(value ?? '').replace(/[&<>"]/g, char => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;'}[char]));
    window.ST = { workspaceMode: 'script' };
    window.STUDIO_WAVE2_STATE = {};
    window.STUDIO_V3_STATE = {};
    window.STUDIO_W4_STATE = {};
    window.STUDIO_WORKSPACE_LAYOUT = {};
    window.STUDIO_W5_STATE = {};
    window.studioCurrentSceneId = () => 7;
    window.studioSceneRecord = () => ({ scene, project });
    window.eval(source('studio-app.js'));
    window.LightekStudioApp.prepare({ scene, project });
    window.app.innerHTML = window.LightekStudioApp.story({ scene, project }, 'script');
    const control = action => window.app.querySelector(`[data-a="${action}"]`);
    await until(() => !control('studioScriptGenerate')?.disabled);
    window.A.studioScriptExample();
    const draft = window.app.querySelector('[data-studio-script]');
    assert.match(draft.value, /\[\[SHOT: WIDE @ 0\]\]/);
    await window.A.studioScriptGenerate(control('studioScriptGenerate'));
    assert(window.app.querySelector('video[src="/preview.mp4"]'));
    assert.match(window.app.querySelector('ol').textContent, /7s/);
    assert(control('studioScriptOpen'));

    draft.value = draft.value.replace('CLOSE @ 7', 'CLOSE @ 8');
    draft.dispatchEvent(new window.Event('input', { bubbles: true }));
    await window.A.studioScriptGenerate(control('studioScriptGenerate'));
    assert.match(window.app.querySelector('ol').textContent, /8s/);
    assert.equal(requests[1].cast_asset_id, 10);
    assert.notEqual(requests[1].request_key, requests[0].request_key);
    console.log((dashboard ? 'Dashboard' : 'PWA') + ': script entry, bench example, preview and edited cuts passed');
  } finally {
    window.close();
  }
}

(async () => { await check(false); await check(true); })().catch(error => { console.error(error); process.exitCode = 1; });
