const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('jsdom');
const bundle = fs.readFileSync(path.resolve(__dirname, '../../public/lightek/studio-unified.js'), 'utf8');

async function workspace(dashboard) {
  const dom = new JSDOM(dashboard
    ? '<div data-unified-studio data-site-id="2" data-scene-id="7" data-home="/dashboard/studio-broadcasting"></div>'
    : '<div id="app"></div>', {
    url: 'https://studio.example/' + (dashboard ? 'dashboard/studio-broadcasting/workspace/7' : 'lightek/index.html#/studio/7'),
    runScripts: 'outside-only', pretendToBeVisual: true
  });
  const {window} = dom;
  const calls = [];
  const result = action => {
    calls.push(action);
    if (action.endsWith('bootstrap')) return {projects:[{id:3,name:'Production',unassigned_scenes:[{id:7,name:'Pilot',settings:{},lock_version:1}]}]};
    if (action.endsWith('assets.list')) return {assets:[]};
    if (action.endsWith('operations.list')) return {operations:[],publications:[]};
    if (action.endsWith('ai.jobs')) return [];
    throw Error('Optional AI engine unavailable');
  };
  window.nevaeh = {
    execute: async request => ({result:result(request.capability)}),
    parseResponse: async response => response
  };
  window.fetch = async (_url, options) => ({status:'completed',result:result(JSON.parse(options.body).capability)});
  window.eval(bundle);
  if (!dashboard) assert.equal(window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7'),true);
  for (let i=0; i<100 && !window.document.querySelector('.ls-shell'); i++) await new Promise(resolve=>setTimeout(resolve,10));
  assert.equal(window.document.querySelector('h1')?.textContent,'Timeline & Edit');
  assert(!calls.some(action=>action.endsWith('ai.status')), 'Editing must open without querying optional AI engine status');
  const tools = window.document.querySelector('[aria-label="More Studio tools"]');
  const links = Object.fromEntries([...tools.querySelectorAll('a')].map(link=>[link.textContent,link.getAttribute('href')]));
  if (dashboard) {
    assert.match(links['Music & audio'],/workspace\/7\?advanced=1&workspace=music&site_id=2$/);
    assert.equal(links['Photo & graphics'],'/dashboard/studio/editors/photo/new?site_id=2');
    assert.equal(links['Full video editor'],'/dashboard/studio/editors/video/new?site_id=2');
  } else {
    assert.equal(links['Music & audio'],'#/studio/7/music');
    assert.equal(links['Animation & characters'],'#/studio/7/stage');
    assert.equal(links['Full video editor'],undefined);
    for (const native of ['music','stage','scene','camera','script']) {
      window.history.replaceState(null,'',`#/studio/7/${native}`);
      const before = window.document.querySelector('#app').firstChild;
      assert.equal(window.LightekUnifiedStudio.pwa(window.document.querySelector('#app'),'7'),false, native);
      assert.equal(window.document.querySelector('#app').firstChild,before,'Native renderer must retain ownership');
    }
    window.LightekUnifiedStudio.leave();
  }
  window.close();
}

(async()=>{
  await workspace(true);
  await workspace(false);
  console.log('Studio core access: Dashboard editing, editor links and PWA native route handoff passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
