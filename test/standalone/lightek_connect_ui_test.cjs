// npm install --no-save jsdom; node test/standalone/lightek_connect_ui_test.cjs
const {JSDOM} = require('jsdom');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const source = fs.readFileSync('public/lightek-connect/workspace.js', 'utf8');
const tick = () => new Promise(resolve => setTimeout(resolve, 10));
(async () => {
  for (const platform of ['wordpress', 'shopify']) {
    const requests = [];
    const dom = new JSDOM(`<main id="lightek-connect" data-platform="${platform}" data-api="/api/connect" data-nonce="nonce"></main>`, {url: 'https://lightekmcg.com/connect/shopify', runScripts:'outside-only'});
    let paired = false;
    dom.window.shopify = {idToken: async () => 'fresh-session-token'};
    dom.window.fetch = async (url, options) => {
      requests.push({url, options});
      let status = 200, body = {};
      if (url.endsWith('/pair')) paired = true;
      else if (!paired) {status = 401; body = {error:'Not connected'};}
      else if (url.endsWith('/workspace')) body = {agency:{name:'Agency'},sites:[{id:12,name:'<img src=x onerror=alert(1)>',host:'client.example.com'}], launches:[], capabilities:[{id:'servers',label:'Servers',path:'/dashboard/servers'}]};
      else if (url.endsWith('/management') || url.endsWith('/dashboard')) body = {url:'https://client.example.com/connect/management?code=abc'};
      else if (options.method === 'PATCH') body = {verified:true, name:'New name'};
      return {status, ok:status<400, json:async()=>body};
    };
    dom.window.eval(source); await tick();
    const root = dom.window.document.querySelector('main');
    const button = label => [...root.querySelectorAll('button')].find(b=>b.textContent===label);
    assert(button('Connect agency'));
    root.querySelector('input').value = 'pairing-code'; button('Connect agency').click(); await tick();
    assert(root.textContent.includes('Connected to Agency'));
    assert.equal(root.querySelectorAll('img').length, 0, 'API text must never execute markup');
    button('Save website name').click(); await tick();
    assert(root.textContent.includes('saved and verified'));
    button('Manage client instance').click(); await tick();
    assert(root.querySelector('a[href^="https://client.example.com/connect/management"]'));
    assert.equal(root.querySelectorAll('iframe').length,0);
    for (const {options} of requests) {
      if (platform === 'shopify') assert.equal(options.headers.Authorization,'Bearer fresh-session-token');
      else assert.equal(options.headers['X-WP-Nonce'],'nonce');
    }
    console.log(`${platform}: pairing, safe rendering, edit, handoff, and authentication checks passed`);
    dom.window.close();
  }
})().catch(error=>{console.error(error); process.exitCode=1;});
