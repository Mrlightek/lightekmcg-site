const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const escape=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function client(identity=true){
 const calls=[],events={},ctx={R:{},AF:{},A:{},E:escape,URL,Date,Intl,Set,console,
  me:()=>identity,meProfile:()=>identity?{id:7}:null,render:()=>{},addEventListener:(name,fn)=>{events[name]??=[];events[name].push(fn)},
  signInHref:h=>'/session/new?return_to='+encodeURIComponent('/lightek/index.html'+h),
  document:{querySelector:()=>null},location:{hash:'#/membership',assign:u=>calls.push({redirect:u})},
  fetch:async(url,options)=>{calls.push({url,options});return {data:{current_plan:'community',enabled:true,plans:[{key:'community',name:'Community',price_cents:0,features:['Free community']},{key:'personal',name:'Personal',price_cents:999,available:true,features:['Your own backend']}],youtube_revenue:[]}}}};
 ctx.window={nevaeh:{csrfHeaders:()=>({'X-CSRF-Token':'csrf'}),parseResponse:async r=>r.data},LightekStorefront:{state:{bootstrap:{}}}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('public/lightek/membership.js','utf8'),ctx);return {ctx,calls,events};
}
test('membership reads real API contract and renders prices in dollars',async()=>{
 const {ctx,calls}=client();await ctx.AF.membership();const html=ctx.R.membership();assert.match(html,/\$9\.99/);assert.match(html,/Get my instance/);assert.equal(calls[0].url,'/api/lightek/pwa/membership');assert.equal(calls[0].options.credentials,'same-origin');
});
test('guests receive free signup and return-to-membership sign in',async()=>{
 const {ctx}=client(false);await ctx.AF.membership();const html=ctx.R.membership();assert.match(html,/\/sign_up\?return_to=/);assert.match(html,/Sign in to upgrade/);assert.doesNotMatch(html,/data-a="membershipBuy"/);
});
test('return from checkout does not claim payment success',()=>{
 const {ctx}=client();assert.match(ctx.R.membership('processing'),/does not activate/);assert.doesNotMatch(ctx.R.membership('processing'),/Payment successful/);
});
test('plan text is escaped',async()=>{
 const {ctx}=client();ctx.fetch=async()=>({data:{current_plan:'<script>',plans:[{key:'community',name:'<img onerror=x>',price_cents:0,features:['<script>']}]}});await ctx.AF.membership();const html=ctx.R.membership();assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<img onerror/);
});
test('checkout posts only selected plan with csrf headers',async()=>{
 const {ctx,calls}=client();ctx.fetch=async(url,options)=>{calls.push({url,options});return {data:{checkout_url:'https://checkout.stripe.com/c/test'}}};await ctx.A.membershipBuy({dataset:{plan:'personal'}});assert.equal(calls[0].url,'/api/lightek/pwa/membership/checkout');assert.deepEqual(JSON.parse(calls[0].options.body),{plan:'personal'});assert.equal(calls[0].options.headers['X-CSRF-Token'],'csrf');assert.equal(calls[1].redirect,'https://checkout.stripe.com/c/test');
});
test('unsafe checkout URLs stay on membership screen',async()=>{
 const {ctx,calls}=client();ctx.fetch=async()=>({data:{checkout_url:'javascript:alert(1)'}});await ctx.A.membershipBuy({dataset:{plan:'personal'}});assert.equal(calls.length,0);assert.match(ctx.R.membership(),/secure destination/);
});
test('services page retains secondary navigation after primary navigation simplifies',()=>{
 const {ctx}=client();ctx.window.LightekStorefront.state.bootstrap={navigation:[{href:'#/studio',label:'Studio'},{href:'#/money',label:'Money'}],services:[{href:'#/studio',label:'Studio'}]};const html=ctx.R.services();assert.equal((html.match(/href="#\/studio"/g)||[]).length,1);assert.match(html,/#\/membership/);assert.match(html,/#\/money/);
});

test('creator earnings lead with actual views and effective earnings per thousand',async()=>{const {ctx}=client();ctx.fetch=async()=>({data:{current_plan:'personal',plans:[],youtube_revenue:[{video_id:'abcdefghijk',views:10000,creator_cents:800,earnings_per_thousand_views_cents:80,period_start:'2026-01-01',period_end:'2026-01-31'}]}});await ctx.AF.membership();const html=ctx.R.membership();assert.match(html,/10,000 views/);assert.match(html,/\$8\.00 estimated earnings/);assert.match(html,/\$0\.80 per 1,000 views/);assert.match(html,/How view earnings are calculated/);});

test('Studio exit returns to the main community from a member host and uses local home otherwise',()=>{
 const {ctx,events}=client();
 let link,insertions=0;
 const app={before:element=>{link=element;insertions++;}};
 ctx.document={
  querySelector:selector=>selector==='#app'?app:selector==='#studio-app-exit'?link:null,
  createElement:()=>({setAttribute(name,value){this[name]=value;}})
 };
 const refresh=()=>events['lightek.bootstrap.ready'].forEach(callback=>callback());
 refresh();
 assert.equal(link.href,'#/home');
 ctx.window.LightekStorefront.state.bootstrap.member_source={origin:'https://lightek.example'};
 refresh();
 assert.equal(link.href,'https://lightek.example/lightek/index.html#/home');
 assert.match(link.textContent,/Back to app/);
 assert.equal(insertions,1);
 ctx.window.LightekStorefront.state.bootstrap.member_source={origin:'javascript:alert(1)'};
 refresh();
 assert.equal(link.href,'#/home');
});
