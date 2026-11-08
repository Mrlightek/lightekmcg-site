/* Server-owned execution contracts; this editor only builds structured inputs. */
(() => {
  function boot() {
    const root = document.querySelector('[data-nevaeh-center]');
    if (!root || root.dataset.ready) return;
    root.dataset.ready = '1';
    const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
    const jsonInput = root.querySelector('[data-sections-json]');
    const stepsEl = root.querySelector('[data-worker-steps]');
    const contract = JSON.parse(root.querySelector('[data-action-contract]')?.textContent || '{}');
    let steps = JSON.parse(jsonInput?.value || '[]');
    let jsonDirty = false;
    const showError = (selector, message) => { const el = root.querySelector(selector); el.textContent = message; el.hidden = !message; };
    const defaults = action => action === 'studio.project.create' ? {name:'New production'} : action === 'content.generate' ? {format:'caption',context:{topic:'Opening night'}} : {};
    function renderSteps() {
      if (!stepsEl) return;
      stepsEl.innerHTML = steps.map((step, index) => `<section class="nc-step" data-step="${index}"><header><strong>STEP ${String(index + 1).padStart(2,'0')}</strong><div class="nc-links"><button type="button" class="nc-button secondary" data-step-move="-1" aria-label="Move step up">↑</button><button type="button" class="nc-button secondary" data-step-move="1" aria-label="Move step down">↓</button><button type="button" class="nc-button secondary" data-step-remove aria-label="Remove step">×</button></div></header><div class="nc-grid2"><label>Step ID<input data-step-id value="${esc(step.id)}" required pattern="[a-z][a-z0-9_]{0,39}"></label><label>Service / action<select data-step-action>${Object.entries(contract).map(([key,value])=>`<option value="${esc(key)}" ${key===step.action?'selected':''}>${esc(value.label)}</option>`).join('')}</select></label></div><div class="nc-grid2">${(contract[step.action]?.fields || []).map(field=>{const value=step.inputs?.[field];return `<label>${esc(field.replaceAll('_',' '))}${['data','context'].includes(field)?`<textarea rows="4" data-step-input="${field}">${esc(typeof value==='object'?JSON.stringify(value,null,2):value||'{}')}</textarea>`:`<input data-step-input="${field}" value="${esc(value)}" ${['description','profile_id'].includes(field)?'':'required'}>`}</label>`;}).join('')}</div><label>Depends on (earlier step IDs, comma separated)<input data-step-deps value="${esc(Array.isArray(step.depends_on)?step.depends_on.join(', '):step.depends_on)}"></label></section>`).join('');
      jsonInput.value = JSON.stringify(steps, null, 2); jsonDirty = false;
    }
    function readSteps() {
      steps = [...stepsEl.querySelectorAll('[data-step]')].map(el => {
        const inputs = {};
        el.querySelectorAll('[data-step-input]').forEach(input => {if(input.value.trim()) inputs[input.dataset.stepInput] = ['data','context'].includes(input.dataset.stepInput) ? JSON.parse(input.value) : input.value;});
        return {id:el.querySelector('[data-step-id]').value,action:el.querySelector('[data-step-action]').value,inputs,depends_on:el.querySelector('[data-step-deps]').value.split(',').map(v=>v.trim()).filter(Boolean)};
      });
    }
    function importJSON() {
      const parsed = JSON.parse(jsonInput.value);
      if(!Array.isArray(parsed)||!parsed.length||parsed.length>20||parsed.some(row=>!row||!contract[row.action]||typeof row.inputs!=='object'||Array.isArray(row.inputs)||!row.inputs)) throw new Error('Use 1–20 supported action sections with input objects.');
      steps=parsed;renderSteps();showError('[data-worker-error]','');
    }
    renderSteps();
    jsonInput?.addEventListener('input',()=>{jsonDirty=true;});
    root.querySelector('[data-worker-form]')?.addEventListener('submit',event=>{try{if(jsonDirty)importJSON();else readSteps();jsonInput.value=JSON.stringify(steps);}catch(error){event.preventDefault();showError('[data-worker-error]',error.message);}});
    stepsEl?.addEventListener('change',event=>{if(event.target.matches('[data-step-action]')){const index=Number(event.target.closest('[data-step]').dataset.step);try{readSteps();steps[index].inputs=defaults(steps[index].action);renderSteps();}catch(error){showError('[data-worker-error]',error.message);}}});
    root.addEventListener('click',event=>{
      const target=event.target.closest('button');if(!target)return;
      if(target.matches('[data-add-step],[data-step-move],[data-step-remove],[data-import-sections]')){
        try{
          if(target.matches('[data-import-sections]'))return importJSON();
          if(jsonDirty)importJSON();else readSteps();
          const index=Number(target.closest('[data-step]')?.dataset.step);
          if(target.matches('[data-add-step]')){if(steps.length>=20)throw new Error('Use at most 20 steps.');let suffix=steps.length+1;while(steps.some(s=>s.id===`step_${suffix}`))suffix++;steps.push({id:`step_${suffix}`,action:'studio.project.create',inputs:defaults('studio.project.create'),depends_on:[]});}
          if(target.matches('[data-step-remove]')){if(steps.length===1)throw new Error('Keep at least one execution step.');steps.splice(index,1);}
          if(target.matches('[data-step-move]')){const other=index+Number(target.dataset.stepMove);if(other>=0&&other<steps.length)[steps[index],steps[other]]=[steps[other],steps[index]];}
          renderSteps();showError('[data-worker-error]','');
        }catch(error){showError('[data-worker-error]',error.message);}
      }
    });
    root.querySelector('[data-capability-search]')?.addEventListener('input',event=>{const query=event.target.value.toLowerCase();root.querySelectorAll('[data-capability-row]').forEach(row=>{row.hidden=!row.textContent.toLowerCase().includes(query);});});
    const play=root.querySelector('[data-writing-playground]');
    async function post(url,data){const response=await fetch(url,{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':document.querySelector('meta[name=csrf-token]').content},body:JSON.stringify(data)});const result=await response.json();if(!response.ok)throw new Error(result.error||'Request failed');return result;}
    play?.addEventListener('change',event=>{if(event.target.name==='profile_id'){const format=event.target.selectedOptions[0]?.dataset.format;if(format)play.elements.format.value=format;}});
    play?.addEventListener('submit',async event=>{event.preventDefault();const status=play.querySelector('[data-writing-status]'),button=play.querySelector('button:not([type=button])');button.disabled=true;status.textContent='Writing…';try{const data=new FormData(play),context={};for(const [key,value] of data){const match=/^context\[([^\]]+)\]$/.exec(key);if(match&&value.trim())context[match[1]]=value;}const result=await post(play.action,{profile_id:data.get('profile_id'),format:data.get('format'),context});play.querySelector('[data-writing-output]').value=result.text;status.textContent=`Draft ready · ${result.provider}`;const evidence=play.querySelector('[data-inference-evidence]');if(evidence){evidence.hidden=false;evidence.textContent=JSON.stringify({matched_rule:result.matched_rule,match_score:result.match_score,fallback:result.fallback,matches:result.matches,model_sha256:result.model_sha256},null,2);}}catch(error){status.textContent=error.message;}finally{button.disabled=false;}});
    play?.querySelector('[data-sample-context]')?.addEventListener('click',async event=>{event.target.disabled=true;try{const result=await post(play.dataset.sampleUrl,{});for(const [key,value] of Object.entries(result)){const field=play.elements.namedItem(`context[${key}]`);if(field)field.value=value;}play.querySelector('[data-writing-status]').textContent='Fictional example loaded.';}catch(error){play.querySelector('[data-writing-status]').textContent=error.message;}finally{event.target.disabled=false;}});
    play?.querySelector('[data-copy-draft]')?.addEventListener('click',async()=>{const output=play.querySelector('[data-writing-output]');try{await navigator.clipboard.writeText(output.value);play.querySelector('[data-writing-status]').textContent='Draft copied.';}catch{output.select();play.querySelector('[data-writing-status]').textContent='Select and copy the draft.';}});
    const inferenceForm=root.querySelector('[data-inference-form]'),inferenceInput=root.querySelector('[data-inference-json]'),inferenceEl=root.querySelector('[data-inference-rules]');
    let inferenceRules=JSON.parse(inferenceInput?.value||'[]'),inferenceDirty=false;
    function renderInference(){if(!inferenceEl)return;inferenceEl.innerHTML=inferenceRules.map((rule,index)=>`<section class="nc-step" data-inference-rule="${index}"><header><strong>RULE ${index+1}</strong><button type="button" class="nc-button secondary" data-remove-inference-rule>Remove</button></header><div class="nc-grid2"><label>Rule ID<input data-rule-field="id" value="${esc(rule.id)}" required></label><label>Output<select data-rule-field="format">${['caption','post','script','description'].map(format=>`<option ${format===rule.format?'selected':''}>${format}</option>`).join('')}</select></label></div><label>Topic keywords (comma separated)<input data-rule-field="keywords" value="${esc((rule.keywords||[]).join(', '))}"></label><div class="nc-grid2"><label>Weight (0–10)<input type="number" min="0" max="10" step="0.1" data-rule-field="weight" value="${esc(rule.weight??1)}"></label><label>Required context fields<input data-rule-field="requires" value="${esc((rule.requires||[]).join(', '))}"></label></div><label>Template blocks (one per line)<textarea rows="5" data-rule-field="templates">${esc((rule.templates||[]).join('\n'))}</textarea></label><small>Fields: {topic}, {audience}, {goal}, {obstacle}, {setting}, {protagonist}, {companion}, {facts}, {call_to_action}</small></section>`).join('');inferenceInput.value=JSON.stringify(inferenceRules,null,2);inferenceDirty=false;}
    function readInference(){inferenceRules=[...inferenceEl.querySelectorAll('[data-inference-rule]')].map(row=>{const rule={};row.querySelectorAll('[data-rule-field]').forEach(field=>{const key=field.dataset.ruleField;rule[key]=key==='weight'?Number(field.value):['keywords','requires'].includes(key)?field.value.split(',').map(v=>v.trim()).filter(Boolean):key==='templates'?field.value.split('\n').map(v=>v.trim()).filter(Boolean):field.value;});return rule;});}
    function importInference(){const parsed=JSON.parse(inferenceInput.value);if(!Array.isArray(parsed)||parsed.some(r=>!r||typeof r!=='object'||!Array.isArray(r.templates)||!Array.isArray(r.keywords)))throw new Error('Use an array of rules with keywords and template blocks.');inferenceRules=parsed;renderInference();}
    renderInference();inferenceInput?.addEventListener('input',()=>{inferenceDirty=true;});
    inferenceForm?.addEventListener('submit',event=>{try{if(inferenceDirty)importInference();else readInference();inferenceInput.value=JSON.stringify(inferenceRules);}catch(error){event.preventDefault();showError('[data-inference-error]',error.message);}});
    inferenceForm?.addEventListener('click',event=>{const b=event.target.closest('button');if(!b||!b.matches('[data-add-inference-rule],[data-import-inference],[data-remove-inference-rule]'))return;try{if(b.matches('[data-import-inference]'))return importInference();if(inferenceDirty)importInference();else readInference();if(b.matches('[data-add-inference-rule]')){let suffix=inferenceRules.length+1;while(inferenceRules.some(r=>r.id===`rule_${suffix}`))suffix++;inferenceRules.push({id:`rule_${suffix}`,format:'script',keywords:['studio','premiere'],weight:1,requires:[],templates:['INT. {setting} — DAY','{protagonist}: We need to {goal}.','{companion}: First, we deal with {obstacle}.','{protagonist}: {facts}']});}if(b.matches('[data-remove-inference-rule]'))inferenceRules.splice(Number(b.closest('[data-inference-rule]').dataset.inferenceRule),1);renderInference();showError('[data-inference-error]','');}catch(error){showError('[data-inference-error]',error.message);}});
    const navForm=root.querySelector('[data-navigation-form]'),navInput=root.querySelector('[data-navigation-json]'),navEl=root.querySelector('[data-navigation-rows]');
    let navigation=JSON.parse(navInput?.value||'[]');
    function renderNav(){if(!navEl)return;navEl.innerHTML=navigation.map((row,index)=>`<div class="nc-nav-row" data-nav-row="${index}" draggable="true"><div><button type="button" class="nc-button secondary" data-nav-move="-1" aria-label="Move ${esc(row.label)} up">↑</button> <button type="button" class="nc-button secondary" data-nav-move="1" aria-label="Move ${esc(row.label)} down">↓</button></div><label>Label<input data-nav-field="label" value="${esc(row.label)}" required maxlength="60"></label><label>Group<input data-nav-field="group" value="${esc(row.group)}" required maxlength="60"></label><label>Application path<input data-nav-field="path" value="${esc(row.path)}" ${row.id.startsWith('custom-')?'required':'readonly'}></label><label class="nc-check"><input type="checkbox" data-nav-field="hidden" ${row.hidden?'checked':''}> Hide</label></div>`).join('');}
    function readNav(){navEl.querySelectorAll('[data-nav-row]').forEach(row=>{const item=navigation[Number(row.dataset.navRow)];row.querySelectorAll('[data-nav-field]').forEach(field=>{item[field.dataset.navField]=field.type==='checkbox'?field.checked:field.value;});});}
    renderNav();
    navForm?.addEventListener('submit',event=>{try{readNav();navInput.value=JSON.stringify(navigation);}catch(error){event.preventDefault();showError('[data-navigation-error]',error.message);}});
    navForm?.addEventListener('click',event=>{const b=event.target.closest('button');if(!b)return;readNav();if(b.matches('[data-add-navigation]')){if(navigation.length>=60)return showError('[data-navigation-error]','Use at most 60 sidebar entries.');navigation.push({id:`custom-${crypto.randomUUID()}`,label:'New application',group:'My applications',path:'/dashboard/live',hidden:false});renderNav();}if(b.matches('[data-reset-navigation]')){navigation=[];renderNav();}if(b.matches('[data-nav-move]')){const i=Number(b.closest('[data-nav-row]').dataset.navRow),j=i+Number(b.dataset.navMove);if(j>=0&&j<navigation.length){[navigation[i],navigation[j]]=[navigation[j],navigation[i]];renderNav();}}});
    let dragging=null;
    navEl?.addEventListener('dragstart',event=>{const row=event.target.closest('[data-nav-row]');if(!row)return;readNav();dragging=Number(row.dataset.navRow);event.dataTransfer.setData('text/plain',String(dragging));});
    navEl?.addEventListener('dragover',event=>{if(event.target.closest('[data-nav-row]'))event.preventDefault();});
    navEl?.addEventListener('drop',event=>{const row=event.target.closest('[data-nav-row]');if(!row||dragging===null)return;event.preventDefault();const to=Number(row.dataset.navRow);navigation.splice(to,0,navigation.splice(dragging,1)[0]);dragging=null;renderNav();});
  }
  document.addEventListener('DOMContentLoaded',boot);document.addEventListener('turbo:load',boot);boot();
})();
