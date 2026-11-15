const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
class Element{
  constructor(tag){this.tag=tag;this.children=[];this.value='';this.textContent='';this.disabled=false;}
  append(...nodes){this.children.push(...nodes);}
  setAttribute(key,value){this[key]=value;}
  set innerHTML(_value){throw Error('Task input UI must not interpolate HTML');}
}
const source=fs.readFileSync('public/nevaeh/os.js','utf8');
const start=source.indexOf('function renderLanguageInputs(h){'),stop=source.indexOf("\n$('#my').onclick",start);
assert(start>=0&&stop>start);
function setup(ask){
  const receipt=new Element('div');let serial=0;const shown=[];
  const context={document:{createElement:tag=>new Element(tag)},$:()=>receipt,think:0,hist:[],crypto:{randomUUID:()=>`test-request-${++serial}`},NEVAEH:{ask},renderTrail(){},show(value){shown.push(value);}};
  vm.runInNewContext(source.slice(start,stop),context);
  const thought={q:'every 60 minutes, inspect member',ag:{id:7},m:0,r:{language_request:{binding_id:9,fingerprint:'known-fingerprint',interval_minutes:60,slots:{id:'integer',name:'string',speed:'number',enabled:'boolean'}}}};
  context.renderLanguageInputs(thought);return {form:receipt.children[0],context,shown};
}
test('missing inputs preserve typed fields and recurring intent as data',async()=>{
  let sent;const {form,shown}=setup(async(...args)=>{sent=args;return {status:'pending'};});
  const labels=form.children.filter(node=>node.tag==='label');assert.equal(labels.length,4);
  const values=['17','<script>literal</script>','0.5','yes'];labels.forEach((label,index)=>label.children[0].value=values[index]);
  assert.equal(labels[2].children[0].step,'any');
  await form.onsubmit({preventDefault(){}});
  assert.equal(sent[3].binding_id,9);assert.equal(sent[3].binding_fingerprint,'known-fingerprint');assert.equal(sent[3].interval_minutes,60);
  assert.equal(sent[3].language_slots.name,'<script>literal</script>');assert.equal(sent[3].language_slots.id,'17');assert.equal(shown.length,1);
});
test('retrying identical inputs reuses the action request key',async()=>{
  const calls=[];const {form,context}=setup(async(...args)=>{calls.push(args);if(calls.length===1)throw Error('Temporary network failure');return {status:'pending'};});
  form.children.filter(node=>node.tag==='label').forEach(label=>label.children[0].value='1');
  await form.onsubmit({preventDefault(){}});assert.equal(context.think,0);
  await form.onsubmit({preventDefault(){}});assert.equal(calls[0][3].request_key,calls[1][3].request_key);
});

test('campaign receipts show safe review links as text and ignore external URLs',()=>{
  const start=source.indexOf('function renderReceipt(a){'),end=source.indexOf('\n',start);
  assert(start>=0 && end>start);
  const receipt=new Element('div');receipt.replaceChildren=function(){this.children=[];};
  const context={document:{createElement:tag=>new Element(tag)},$:()=>receipt};
  vm.runInNewContext(source.slice(start,end),context);
  context.renderReceipt({result:{text:'Draft ready',links:[{label:'<Review draft>',url:'/dashboard/studio-broadcasting/workspace/4'},{label:'Preview',url:'/rails/active_storage/blobs/test'},{label:'Bad',url:'javascript:alert(1)'},{label:'External',url:'//example.com'}]}});
  const links=receipt.children.filter(node=>node.tag==='a');
  assert.equal(links.length,2);assert.equal(links[0].textContent,'<Review draft>');
  assert.equal(links[0].href,'/dashboard/studio-broadcasting/workspace/4');
});
