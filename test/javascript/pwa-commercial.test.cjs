const test=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs');
const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function client(file,hash='#/support/9',identity=7){
 const calls=[],listeners={},storage=new Map();let response={creator:{id:9,name:'A creator'},enabled:true,monthly_cents:500,earnings:[],payments:[]};
 const ctx={R:{},AF:{},A:{},E,Number,Date,Intl,URL,console,crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},me:()=>!!identity,meProfile:()=>identity?{id:identity}:null,
  render:()=>{},toast:()=>{},signInHref:()=>'/session/new',addEventListener:()=>{},location:{hash,assign:url=>calls.push({redirect:url})},
  sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},document:{addEventListener:(name,fn)=>listeners[name]=fn,getElementById:()=>({value:'5'})},
  FormData:class {constructor(form){this.values=form.values;}get(k){return this.values[k]}has(k){return !!this.values[k]}},
  fetch:async(url,options)=>{calls.push({url,options});return {data:response}}};
 ctx.window={nevaeh:{csrfHeaders:()=>({'X-CSRF-Token':'csrf'}),parseResponse:async r=>r.data}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('public/lightek/'+file,'utf8'),ctx);
 return {ctx,calls,listeners,set:data=>response=data};
}
test('creator support displays separately accepted fees before secure checkout',async()=>{
 const c=client('creator-support.js');await c.ctx.AF.support();c.set({kind:'tip',principal_cents:500,fee_cents:51,subtotal_cents:551});
 await c.ctx.A.supportQuote({dataset:{kind:'tip'}});const html=c.ctx.R.support();assert.match(html,/Creator receives: <strong>\$5.00/);assert.match(html,/Support fees: \$0.51/);assert.match(html,/\$5.51/);
 c.set({checkout_url:'https://checkout.example.com/session'});await c.ctx.A.supportPay();
 const body=JSON.parse(c.calls.find(call=>call.url?.endsWith('/checkout')).options.body);assert.equal(body.accepted_fee_cents,51);assert.equal(body.principal_cents,500);assert.equal(body.request_key,'11111111-1111-4111-8111-111111111111');assert.equal(c.calls.at(-1).redirect,'https://checkout.example.com/session');
});
test('anonymous support page offers sign in instead of payment controls',async()=>{
 const c=client('creator-support.js','#/support/9',null);await c.ctx.AF.support();const html=c.ctx.R.support();assert.match(html,/Sign in/);assert.doesNotMatch(html,/data-a="supportQuote"/);
});
test('past due or disabled creator still exposes monthly cancellation',async()=>{
 const c=client('creator-support.js');c.set({creator:{id:9,name:'Creator'},enabled:false,subscribed:false,subscription_id:12,subscription_status:'past_due',cancel_at_period_end:false,payments:[]});await c.ctx.AF.support();assert.match(c.ctx.R.support(),/Cancel monthly renewal/);assert.match(c.ctx.R.support(),/past_due/);
});
test('checkout return and pending payment never announce a paid gift',async()=>{
 const c=client('creator-support.js');c.set({creator:{id:9,name:'Creator'},enabled:true,monthly_cents:500,payments:[{id:1,kind:'gift',principal_cents:500,fee_cents:51,status:'pending_payment',confirmed:false}],gifts:[]});await c.ctx.AF.support();const html=c.ctx.R.support('processing');assert.match(html,/does not confirm payment/);assert.doesNotMatch(html,/Payment confirmed|Confirmed live gifts/);assert.match(html,/Resume secure checkout/);
});
test('creator names and gift names are escaped',async()=>{
 const c=client('creator-support.js');c.set({creator:{id:9,name:'<img onerror=x>'},enabled:true,monthly_cents:500,gifts:[{id:1,principal_cents:100,supporter:'<script>'}],payments:[]});await c.ctx.AF.support();const html=c.ctx.R.support();assert.match(html,/&lt;img/);assert.match(html,/&lt;script&gt;/);assert.doesNotMatch(html,/<script>|<img onerror/);
});
test('YouTube submission sends explicit author consent and selected audience with csrf',async()=>{
 const c=client('youtube-publishing.js','#/youtube/17');c.set({post:{id:17,title:'Film'},enabled:true,upload:null});await c.ctx.AF.youtube();assert.match(c.ctx.R.youtube(),/all necessary rights/);
 c.set({upload:{status:'queued',key:'key'}});await c.listeners.submit({target:{matches:()=>true,values:{consent:true,kids:'false'}},preventDefault:()=>{}});
 const call=c.calls.at(-1),body=JSON.parse(call.options.body);assert.equal(call.url,'/api/lightek/pwa/youtube/posts/17');assert.deepEqual(body,{consent:true,made_for_kids:false});assert.equal(call.options.headers['X-CSRF-Token'],'csrf');assert.equal(call.options.credentials,'same-origin');assert.match(c.ctx.R.youtube(),/queued/);
});
test('YouTube publishing does not label queued upload as playable and offers withdrawal',async()=>{
 const c=client('youtube-publishing.js','#/youtube/17');c.set({post:{id:17,title:'Film'},enabled:true,upload:{status:'processing',key:'key',video_id:null}});await c.ctx.AF.youtube();const html=c.ctx.R.youtube();assert.match(html,/Remove from Lightek YouTube/);assert.doesNotMatch(html,/Watch on YouTube/);
});
