const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
async function hydrate(urls,{post,ok=true}={}){
 let intersect;const calls=[];const nodes=urls.map(url=>({dataset:{remoteContent:url},innerHTML:''}));
 const ctx={URL,Date,Map,console,AbortSignal,
  E:v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),
  document:{getElementById:()=>({}),querySelectorAll:()=>nodes},
  IntersectionObserver:class{constructor(cb){intersect=cb}observe(){}unobserve(){}},MutationObserver:class{observe(){}},
  fetch:async(url,options)=>{calls.push({url,options});return {ok,text:async()=>JSON.stringify(post||{id:17,visibility:'public',audience:'everyone',content:'From member server',metadata:{},media:[]})}}};
 vm.createContext(ctx);vm.runInContext(fs.readFileSync('public/lightek/remote-content.js','utf8'),ctx);
 intersect(nodes.map(target=>({isIntersecting:true,target})));await tick();await tick();return {calls,nodes};
}
test('member content loads directly without cookies or redirects',async()=>{const {calls,nodes}=await hydrate(['https://member.example/api/lightek/network/posts/17']);assert.equal(calls[0].options.credentials,'omit');assert.equal(calls[0].options.redirect,'error');assert.match(nodes[0].innerHTML,/From member server/);assert.match(nodes[0].innerHTML,/https:\/\/member.example\/lightek\/index.html#\/post\/17/)});
test('repeat references share one in-flight request and both finish',async()=>{const {calls,nodes}=await hydrate(Array(2).fill('https://member.example/api/lightek/network/posts/17'));assert.equal(calls.length,1);assert(nodes.every(n=>n.dataset.remoteLoaded==='true'));assert(nodes.every(n=>n.innerHTML.includes('From member server')))});
test('private source posts are never rendered centrally',async()=>{const {nodes}=await hydrate(['https://member.example/api/lightek/network/posts/17'],{post:{visibility:'private',audience:'everyone',content:'SECRET',metadata:{}}});assert.doesNotMatch(nodes[0].innerHTML,/SECRET/);assert.match(nodes[0].innerHTML,/no longer public/)});
test('invalid reference paths are rejected before fetching',async()=>{for(const url of ['javascript:alert(1)','http://member.example/api/lightek/network/posts/17','https://member.example/private?token=abc']){const {calls}=await hydrate([url]);assert.equal(calls.length,0)}});
test('source content is escaped and foreign media URLs are omitted',async()=>{const {nodes}=await hydrate(['https://member.example/api/lightek/network/posts/17'],{post:{id:17,visibility:'public',audience:'everyone',content:'<script>alert(1)</script>',metadata:{},media:[{url:'https://evil.example/video',content_type:'video/mp4'}]}});assert.match(nodes[0].innerHTML,/&lt;script&gt;/);assert.doesNotMatch(nodes[0].innerHTML,/<script>|evil\.example/)});
test('one unavailable source produces a local fallback',async()=>{const {nodes}=await hydrate(['https://member.example/api/lightek/network/posts/17'],{ok:false});assert.match(nodes[0].innerHTML,/source instance is unavailable/);assert.equal(nodes[0].dataset.remoteLoaded,'true')});
