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
    assert.equal(root.querySelector('article strong').textContent, 'New name', 'Confirmed name updates the visible site');
    button('Manage client instance').click(); await tick();
    assert(root.querySelector('a[href^="https://client.example.com/connect/management"]'));
    assert(root.textContent.includes('ten minutes'), 'Initial MFA handoff lasts ten minutes');
    button('Manage client instance').click(); await tick();
    assert.equal(root.querySelectorAll('.lc-link').length, 1, 'A new management link replaces the previous link');
    assert.equal(root.querySelectorAll('iframe').length,0);
    for (const {options} of requests) {
      if (platform === 'shopify') assert.equal(options.headers.Authorization,'Bearer fresh-session-token');
      else assert.equal(options.headers['X-WP-Nonce'],'nonce');
    }
    console.log(`${platform}: pairing, safe rendering, edit, handoff, and authentication checks passed`);
    dom.window.close();

    const recovery = new JSDOM(`<main id="lightek-connect" data-platform="${platform}" data-api="/api/connect"></main>`, {url:'https://lightekmcg.com/connect/shopify', runScripts:'outside-only'});
    recovery.window.shopify = {idToken: async () => 'fresh-session-token'};
    let mode = 'outage';
    recovery.window.fetch = async () => {
      if (mode === 'network') throw new TypeError('Failed to fetch');
      if (mode === 'outage') return {status:503, ok:false, json:async()=>{throw new SyntaxError('HTML error page');}};
      if (mode === 'unauthorized') return {status:401, ok:false, json:async()=>{throw new SyntaxError('Empty unauthorized response');}};
      return {status:200, ok:true, json:async()=>({agency:{name:'Recovered'},sites:[], launches:[], capabilities:[]})};
    };
    recovery.window.eval(source); await tick();
    const recoveryRoot = recovery.window.document.querySelector('main');
    const recoveryButton = label => [...recoveryRoot.querySelectorAll('button')].find(b=>b.textContent===label);
    assert(recoveryButton('Retry connection'));
    assert(!recoveryButton('Connect agency'), 'An outage must not be treated as an unpaired connection');
    assert(recoveryRoot.textContent.includes('temporarily unavailable'));
    mode = 'network'; recoveryButton('Retry connection').click(); await tick();
    assert(recoveryRoot.textContent.includes('Unable to reach Lightek'));
    mode = 'success'; recoveryButton('Retry connection').click(); await tick();
    assert(recoveryRoot.textContent.includes('Connected to Recovered'));
    assert(recoveryRoot.textContent.includes('No deployments yet.'));
    mode = 'outage'; recoveryButton('Refresh').click(); await tick();
    assert(recoveryRoot.textContent.includes('Connected to Recovered'), 'Refresh failure preserves the existing workspace');
    mode = 'unauthorized'; recoveryButton('Refresh').click(); await tick();
    assert(recoveryButton('Connect agency'), 'Revoked connections can reconnect');
    assert(!recoveryButton('Refresh'));
    let consumed = 0;
    recovery.window.fetch = async url => {
      if (url.endsWith('/pair')) {consumed++; return {status:200, ok:true, json:async()=>({connection_id:1})};}
      return {status:503, ok:false, json:async()=>({error:'Service unavailable'})};
    };
    recoveryRoot.querySelector('input').value = 'new-code';
    recoveryButton('Connect agency').click(); await tick();
    assert.equal(consumed, 1);
    assert(recoveryButton('Retry connection'), 'Successful pairing followed by an outage retries workspace loading');
    assert(!recoveryButton('Connect agency'), 'Do not ask for another code after successful pairing');
    recoveryButton('Retry connection').click(); await tick();
    assert.equal(consumed, 1, 'Read retry must not repeat the consumed pairing request');
    recovery.window.close();
    console.log(`${platform}: outage, network failure, retry, preserved workspace, and revoked-connection recovery passed`);
  }
})().catch(error=>{console.error(error); process.exitCode=1;});
