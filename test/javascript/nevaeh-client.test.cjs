const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync('public/lightek/nevaeh-client.js', 'utf8');
function client(responses) {
  const calls = [];
  const window = { dispatchEvent() {} };
  const context = { window, document: { querySelector: () => null }, CustomEvent: class {}, Map, Date, setTimeout: fn => fn(),
    fetch: async (url, args) => { calls.push({url,args}); const r = responses.shift(); if (!r) throw Error('unexpected fetch'); return { ok: r.code < 400, status: r.code, json: async () => r.body }; } };
  vm.runInNewContext(source, context);
  return { client: window.nevaeh, calls };
}
test('waits for Dispatch completion without submitting the mutation again', async () => {
  const { client: c, calls } = client([{code:202,body:{status:'running',work_item_id:17}}, {code:202,body:{status:'running'}}, {code:200,body:{status:'completed',result:{post:{id:9}}}}]);
  const r = await c.execute({capability:'community.post.create',payload:{content:'hello'}});
  assert.equal(r.result.post.id,9);
  assert.equal(calls.filter(c=>c.args.method==='POST').length,1);
  assert.equal(calls[1].url,'/api/nevaeh/executions/17');
});
test('surfaces failed jobs instead of reporting success', async () => {
  const {client:c}=client([{code:202,body:{work_item_id:2}}, {code:200,body:{status:'failed',error:'Join this community to participate'}}]);
  await assert.rejects(c.execute({capability:'community.post.create'}), /Join this community/);
});
test('immediate completion and CSRF token are preserved', async () => {
  const {client:c,calls}=client([{code:200,body:{status:'completed',result:{id:3}}}]);
  c.csrfToken='csrf-value';
  const r=await c.execute({capability:'community.join'});
  assert.equal(r.result.id,3);
  assert.equal(calls[0].args.headers['X-CSRF-Token'],'csrf-value');
});
test('HTTP failure is actionable', async()=>{
  const {client:c}=client([{code:401,body:{error:'Authentication required'}}]);
  await assert.rejects(c.execute({capability:'messages.list'}), /Authentication required/);
});
