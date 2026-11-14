const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {JSDOM}=require('jsdom');
(async()=>{
 const dom=new JSDOM('<main id="lightek-studio-dashboard"><div id="app"></div></main>',{url:'https://studio.test/#/studio/7/look',runScripts:'outside-only'});
 const context=dom.getInternalVMContext(),evaluate=s=>vm.runInContext(s,context),document=dom.window.document;
 evaluate(`
 const app=document.getElementById('app'),requests=[];
 const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const record={scene:{id:7,settings:{native_revision:0}}},studioCurrentSceneId=()=>7,toast=v=>window.lastToast=v;
 window.LightekStudioProduction={mode:()=> 'look'};let failed=false;
 const data={lock_version:0,native_revision:0,look:{exposure:0,gamma:1,saturation:1,contrast:0,blur:0,glow:0,glow_threshold:1},targets:[0,1].map(slot=>({object_id:10,target:'',slot,name:'Mesh / material '+slot,fields:['color','roughness','metallic','opacity','ior','transmission','emission_strength','emission_color'],linked_fields:['color'],values:{color:[.2,.3,.4,1],emission_color:[1,1,1,1],roughness:.531,metallic:0,opacity:1,ior:1.5,transmission:0,emission_strength:0}}))};
 const A={studioLoad:async()=>{record.scene.settings.native_revision=data.native_revision;render()}};
 const nevaeh={execute:async request=>{requests.push(JSON.parse(JSON.stringify(request)));let result;
 if(request.capability==='studio.workspace.look.status')result=JSON.parse(JSON.stringify(data));
 else if(request.capability==='studio.workspace.material.save'){
  if(!failed){failed=true;throw Error('Connection interrupted');}
  const target=data.targets.find(t=>t.slot===request.payload.slot);Object.assign(target.values,request.payload.values);data.lock_version++;data.native_revision++;result={};
 }else if(request.capability==='studio.workspace.look.save'){data.look={...data.look,...request.payload.look};data.lock_version++;data.native_revision++;result={};}
 else if(request.capability==='studio.workspace.blender.preview')result={operation_id:99,status:'completed',native_revision:data.native_revision,url:'/render.png'};
 return{result};}};
 function render(){app.innerHTML=LightekStudioLook.view(record)}
 `);
 vm.runInContext(fs.readFileSync('public/lightek/studio-look.js','utf8'),context);
 const settle=async()=>{for(let i=0;i<12;i++)await new Promise(r=>setImmediate(r));};
 const change=(form,name,value)=>{const input=document.querySelector(`[data-look-form=${form}] [name=${name}]`);input.value=value;input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));};
 const submit=async form=>{document.querySelector(`[data-look-form=${form}]`).dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await settle();};
 evaluate('render()');await settle();
 change('scene','exposure','1');change('material','roughness','.2');
 await submit('material');assert.match(document.querySelector('[role=alert]').textContent,/Connection interrupted/);await submit('material');
 const material=JSON.parse(evaluate('JSON.stringify(requests.filter(r=>r.capability.endsWith("material.save")))'));
 assert.equal(material[0].payload.request_key,material[1].payload.request_key);assert.deepEqual(material[1].payload.values,{roughness:.2},'unchanged color/quantized inputs must keep source links');
 assert.equal(document.querySelector('[name=exposure]').value,'1','saving a material preserves scene finish draft');
 assert(evaluate('LightekStudioLook.dirty()'));
 const select=document.querySelector('[data-look-target]');select.value='1';select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));
 change('material','metallic','.8');await submit('scene');
 assert.equal(Number(document.querySelector('[name=metallic]').value),0.8,'scene save preserves material draft');
 await dom.window.LightekStudioLook.save();await settle();
 assert(!evaluate('LightekStudioLook.dirty()'));assert.equal(evaluate('data.targets[1].values.metallic'),.8);
 change('material','metallic','.1');document.querySelector('[data-look=reload]').click();await settle();assert.equal(Number(document.querySelector('[name=metallic]').value),.8);assert(!evaluate('LightekStudioLook.dirty()'));
 document.querySelector('[data-look=preview]').click();await settle();assert.equal(document.querySelector('img').getAttribute('src'),'/render.png');
 dom.window.close();console.log('STUDIO_LOOK_DOM_PASS sparse materials slots retry independent drafts global save preview');
})().catch(error=>{console.error(error);process.exit(1)});
