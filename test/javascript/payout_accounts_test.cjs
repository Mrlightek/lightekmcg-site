const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname,'../../public/lightek/payout-accounts.js'),'utf8');
function element(dataset={}) {return {dataset, hidden:false,disabled:false,textContent:'',events:{},children:[],addEventListener(name,fn){this.events[name]=fn;},replaceChildren(...children){this.children=children;}};}
function harness(responses) {
  const opens=[element({payoutOpen:'account-onboarding'}),element({payoutOpen:'account-management'})];
  const error=element(),component=element(),badge=element(),status=element(),refresh=element();
  const nodes={'[data-payout-error]':error,'[data-payout-component]':component,'[data-payout-badge]':badge,'[data-payout-status]':status,'[data-payout-refresh]':refresh};
  const root=element({sessionUrl:'/session',statusUrl:'/status'});
  root.querySelector=selector=>nodes[selector];root.querySelectorAll=()=>opens;
  const events={},requests=[],sdkOptions=[],components=[];let logouts=0;
  const sdk={init(options){sdkOptions.push(options);return {create(name){components.push(name);return {setOnLoadError(fn){this.onError=fn;},setOnExit(fn){this.onExit=fn;}};},logout(){logouts++;return Promise.resolve();}};}};
  const document={querySelector(selector){return selector==='[data-payout-workspace]'?root:selector==='meta[name="csrf-token"]'?{content:'csrf-fixture'}:null;},addEventListener(name,fn){events[name]=fn;},head:{appendChild(){throw Error('unexpected provider script before an explicit action');}}};
  vm.runInNewContext(source,{document,window:{StripeConnect:sdk},AbortController,URL,location:{origin:'https://example.test'},getComputedStyle:()=>({getPropertyValue:()=>''}),fetch:async(url,options)=>{
    requests.push({url,options});const response=responses.shift();if(response instanceof Error)throw response;return {ok:response.ok!==false,headers:{get:()=>response.type||'application/json'},json:async()=>response.data};
  }});
  return {opens,error,component,badge,status,refresh,requests,sdkOptions,components,events,get logouts(){return logouts;}};
}
(async()=>{
  const h=harness([{data:{client_secret:'ephemeral-1',publishable_key:'pk_test_fixture'}},{data:{client_secret:'ephemeral-2',publishable_key:'pk_test_fixture'}},{data:{state:'ready'}}]);
  assert.equal(h.requests.length,0,'never mint sessions merely by loading the page');
  await h.opens[0].events.click();
  assert.equal(h.requests[0].options.headers['X-CSRF-Token'],'csrf-fixture');
  assert.equal(h.requests[0].options.credentials,'same-origin');
  assert.equal(h.requests[0].options.cache,'no-store');
  assert.deepEqual(JSON.parse(h.requests[0].options.body),{component:'account-onboarding'});
  assert.deepEqual(h.components,['account-onboarding']);
  assert.equal(await h.sdkOptions[0].fetchClientSecret(),'ephemeral-1');
  assert.equal(h.requests.length,1,'first credential is consumed once');
  assert.equal(await h.sdkOptions[0].fetchClientSecret(),'ephemeral-2');
  assert.equal(h.requests.length,2,'SDK renewal reauthorizes with the app');
  await h.refresh.events.click();
  assert.equal(h.badge.textContent,'Ready for payouts');
  h.component.children[0].onError({message:'sk_live_private account acct_private'});
  assert(!h.error.textContent.includes('sk_live_private'));
  assert(!h.error.textContent.includes('acct_private'));
  h.events.submit({target:{action:'https://example.test/sign_out',querySelector:()=>({value:'delete'})}});
  assert.equal(h.logouts,1,'app sign out revokes embedded sessions');
  const denied=harness([{ok:false,data:{error:'provider raw sk_live_private'}}]);
  await denied.opens[0].events.click();
  assert.equal(denied.error.hidden,false);
  assert(!denied.error.textContent.includes('sk_live_private'));
  assert.equal(denied.component.children.length,0);
  const expired=harness([{type:'text/html',data:{}}]);
  await expired.opens[0].events.click();
  assert.equal(expired.component.children.length,0,'an HTML login redirect is never treated as a financial session');
  console.log('Payout frontend: consent, CSRF, ephemeral sessions, renewal, sanitized errors and logout passed');
})().catch(error=>{console.error(error);process.exitCode=1;});
