const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{JSDOM}=require('jsdom');
(async()=>{
 const dom=new JSDOM('<main id="lightek-studio-dashboard" data-site-id="2"><div id="app"></div></main>',{url:'https://studio.test/#/studio/7/camera',runScripts:'outside-only'}),w=dom.window,d=w.document,context=dom.getInternalVMContext(),evaluate=code=>vm.runInContext(code,context);
 w.structuredClone=structuredClone;
 evaluate(`const app=document.getElementById('app'),requests=[],ST={loaded:true,busy:false},A={studioLoad:async()=>{}},R={studio:()=>''};
 const E=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])),toast=text=>window.lastToast=text;
 const record={project:{id:4,name:'CPU show'},scene:{id:7,name:'Shot',settings:{resolution_x:1280,resolution_y:720,render_engine:'CYCLES',compute_profile:'custom'},objects:[],lock_version:0}};
 const studioCurrentSceneId=()=>7,studioSceneRecord=()=>record,studioSceneRecords=()=>[record],studioWorkspaceSelectedObject=()=>null;
 const job={id:9,type:'build_scene',status:'failed',cpu_resumable:true,cpu_progress:{profile:'cpu_economy',phase:'rendering_frames',completed_frames:2,total_frames:3,reused_frames:1,elapsed_seconds:2},artifacts:[]};
 const nevaeh={execute:async request=>{requests.push(structuredClone(request));if(request.capability.endsWith('visual.save')){record.scene.settings.compute_profile=request.payload.render_settings.compute_profile;return{result:{lock_version:1}};}if(request.capability.endsWith('render.resume')){job.status='pending';job.cpu_resumable=false;return{result:{operation_id:9,status:'pending'}};}return{result:{operations:[job]}};}};
 window.LightekStudioPerformance={capture(){},leave(){},busy:()=>false,dirty:()=>false};window.LightekStudioMusic={stop(){},busy:()=>false,dirty:()=>false};window.LightekStudioTimeline={stop(){},dirty:()=>false};
 function render(){window.LightekStudioProduction?.render(7)}
 `);
 evaluate(fs.readFileSync('public/lightek/studio-app.js','utf8'));evaluate('LightekStudioApp.prepare=()=>{}');evaluate(fs.readFileSync('public/lightek/studio-production.js','utf8'));evaluate('render()');
 const settle=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));};
 const form=d.querySelector('[data-studio-form=visual]');assert(form);assert.equal(form.elements.compute_profile.value,'custom','existing scenes retain their profile');form.elements.compute_profile.value='cpu_economy';form.dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));await settle();
 assert(evaluate('requests.some(r=>r.capability.endsWith("visual.save"))'),evaluate('window.lastToast'));const saved=JSON.parse(evaluate('JSON.stringify(requests.find(r=>r.capability.endsWith("visual.save")))'));assert.equal(saved.payload.render_settings.compute_profile,'cpu_economy');assert.equal(saved.payload.render_settings.resolution_x,1280,'the UI preserves requested dimensions; the server resolves the bounded render snapshot');
 d.querySelector('[data-production=refresh-jobs]').click();await settle();assert.match(d.querySelector('[data-production-job-list]').textContent,/2 \/ 3 frames/);assert.match(d.querySelector('[data-production-job-list]').textContent,/1 reused/);
 const resume=d.querySelector('[data-production=resume-render]');assert(resume);resume.click();resume.click();await settle();assert.equal(evaluate('requests.filter(r=>r.capability.endsWith("render.resume")).length'),1);assert.equal(d.querySelector('[data-production=resume-render]'),null,'pending work cannot be resumed twice');assert.match(d.querySelector('[data-production-job-list]').textContent,/pending/);
 dom.window.close();console.log('STUDIO_CPU_ECONOMY_DOM_PASS explicit profile save, preserved source dimensions, measured frame progress and single resume handoff without checkout');
})().catch(error=>{console.error(error);process.exit(1)});
