const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {JSDOM}=require('jsdom');

(async()=>{
  const dom=new JSDOM('<!doctype html><main id="lightek-studio-dashboard"><div id="app"></div></main>',{url:'https://studio.test/#/studio/7/shots',runScripts:'outside-only'});
  dom.window.structuredClone=structuredClone;
  const context=dom.getInternalVMContext(),evaluate=source=>vm.runInContext(source,context),document=dom.window.document;
  evaluate(`
    const app=document.getElementById('app'),requests=[],ST={selectedObjectId:null};
    const scene={id:7,name:'Episode',lock_version:0,settings:{fps:24},objects:[{id:1,name:'Wide',object_type:'camera',definition:{}},{id:2,name:'Close',object_type:'camera',definition:{}},{id:3,name:'Lead',object_type:'imported_asset',definition:{character_profile:{}}}]};
    const record={scene,project:{id:4}};let mode='shots',saved=[],revision=0,renderQuoteAttempts=0;
    const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
    const studioSceneRecord=()=>record,studioCurrentSceneId=()=>7,toast=v=>window.lastToast=v;
    const A={studioLoad:async()=>{}};
    window.LightekStudioApp={setQuote:v=>window.quote=v};
    window.LightekStudioProduction={mode:()=>mode,go:(target,id)=>{mode=target;window.lastRoute={target,id}}};
    window.LightekStudioAI={startShot:(id,shot)=>window.generation={id,shot}};
    window.LightekStudioTimeline={dirty:()=>false,save:async()=>{}};
    const nevaeh={execute:async r=>{requests.push(structuredClone(r));const p=r.payload;
      if(r.capability.endsWith('shots.list'))return {result:{shots:structuredClone(saved),lock_version:scene.lock_version,revision}};
      if(r.capability.endsWith('shots.save')){saved=structuredClone(p.shots);revision++;scene.lock_version++;return{result:{revision,lock_version:scene.lock_version}};}
      if(r.capability.endsWith('render.quote')){if(++renderQuoteAttempts===1)throw Error('Pricing unavailable');return{result:{operation_id:101,operation_type:'build_scene',quote:{total_cents:125}}};}
      if(r.capability.endsWith('artifact.use'))return {result:{status:'ready'}};
      return {result:{}};
    }};
    function render(){if(mode==='shots')app.innerHTML=LightekStudioShots.view(record)}
  `);
  vm.runInContext(fs.readFileSync('public/lightek/studio-shots.js','utf8'),context);
  const settle=async()=>{for(let n=0;n<12;n++)await new Promise(resolve=>setImmediate(resolve));};
  const click=(action,index=0)=>{const button=[...document.querySelectorAll('[data-shot]')].filter(b=>b.dataset.shot===action)[index];assert(button,action);button.click();};
  const change=(field,value,index=0)=>{const element=document.querySelectorAll(`[data-shot-form] [name="${field}"]`)[index];element.value=value;element.dispatchEvent(new dom.window.Event('input',{bubbles:true}));};
  evaluate('render()');await settle();
  click('add');assert.equal(document.querySelectorAll('[data-shot-card]').length,1);
  change('name','Opening wide');change('notes','Keep the character and room consistent');change('prompt','A cinematic studio');change('camera_id','2');change('frame_start','25');change('frame_end','48');
  assert(evaluate('LightekStudioShots.dirty()'));
  click('duplicate');assert.equal(document.querySelectorAll('[data-shot-card]').length,2);
  click('up',1);assert.equal(document.querySelector('[name=name]').value,'Opening wide copy');
  click('save');await settle();
  assert.equal(evaluate('saved.length'),2);
  assert.equal(evaluate('saved[0].camera_id'),2);
  assert.equal(evaluate('saved[0].frame_start'),25);
  assert(!evaluate('LightekStudioShots.dirty()'));
  const id=evaluate('saved[0].id');
  click('quote');await settle();assert.match(dom.window.lastToast,/Pricing unavailable/);
  click('quote');await settle();
  const quotes=JSON.parse(evaluate('JSON.stringify(requests.filter(r=>r.capability.endsWith("render.quote")))'));
  assert.equal(quotes.length,2);assert.equal(quotes[0].payload.request_key,quotes[1].payload.request_key,'pricing retry must not create another render');
  assert.equal(quotes[1].payload.shot_id,id);assert.equal(dom.window.quote.operation_type,'build_scene');
  assert.equal(dom.window.lastRoute.target,'deliver');
  evaluate("mode='shots';render()");click('generate');await settle();
  assert.equal(dom.window.generation.shot.prompt,'A cinematic studio');assert.equal(dom.window.generation.shot.id,id);
  evaluate("mode='shots';render()");click('stage');await settle();assert.equal(evaluate('ST.selectedObjectId'),2);
  assert.equal(dom.window.lastRoute.target,'camera');
  evaluate("mode='shots';saved[0].render={operation_id:101,status:'completed',stale:false,artifacts:[{id:99,url:'/shot.mp4',filename:'movie.mp4'}]};LightekStudioShots.view(record)");
  click('refresh');await settle();click('use');await settle();assert.equal(dom.window.lastRoute.target,'edit');
  evaluate("mode='shots';render()");click('remove');assert(evaluate('LightekStudioShots.dirty()'));click('refresh');await settle();
  assert.equal(document.querySelectorAll('[data-shot-card]').length,2,'discard reload restores saved shots');
  dom.window.close();console.log('STUDIO_SHOTS_UI_PASS create duplicate reorder save quote_retry camera genesis handoff discard');
})().catch(error=>{console.error(error);process.exitCode=1});
