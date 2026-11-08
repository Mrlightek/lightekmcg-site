(() => {
  if (window.lightekStarterRuntime) return;
  window.lightekStarterRuntime = true;
  const all = (selector, root) => [...root.querySelectorAll(selector)];
  function mount() {
    document.querySelectorAll('lightek-starter').forEach(host => {
      const template = host.querySelector('template[shadowrootmode]');
      if (template && !host.shadowRoot) host.attachShadow({mode:'open'}).append(template.content.cloneNode(true));
      const root = host.shadowRoot;
      if (!root || host.dataset.wired) return;
      host.dataset.wired = 'true';
      const nav = root.querySelector('nav.m'), burger = root.querySelector('.burger');
      burger?.addEventListener('click', () => { const open = nav?.classList.toggle('open'); burger.setAttribute('aria-expanded', String(!!open)); });
      root.addEventListener('keydown', event => { if (event.key === 'Escape') { nav?.classList.remove('open'); burger?.setAttribute('aria-expanded','false'); } });
      root.addEventListener('click', event => {
        const link = event.target.closest('a[href^="#"]');
        if (!link) return;
        const id = link.getAttribute('href').slice(1);
        if (!id) return;
        const target = all('lightek-starter', document).filter(h => h.dataset.template === host.dataset.template).map(h => h.shadowRoot?.getElementById(id)).find(Boolean) || document.getElementById(id);
        if (target || id === 'top') { event.preventDefault(); nav?.classList.remove('open'); burger?.setAttribute('aria-expanded','false'); if (id === 'top') window.scrollTo({top:0,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'}); else target.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'}); }
      });
      all('[data-tabs]', root).forEach(group => {
        const buttons = all('.tb',group), panes = all('.tp',group);
        group.setAttribute('role','tablist');
        buttons.forEach((button, index) => {
          button.setAttribute('role','tab'); button.setAttribute('aria-selected',String(index === 0));
          button.addEventListener('click', () => { buttons.forEach((item,i) => { item.classList.toggle('on',i===index); item.setAttribute('aria-selected',String(i===index)); }); panes.forEach((pane,i) => { pane.hidden = i!==index; }); });
          button.addEventListener('keydown', event => { if (['ArrowRight','ArrowLeft'].includes(event.key)) { event.preventDefault(); const next = buttons[(index+(event.key==='ArrowRight'?1:buttons.length-1))%buttons.length]; next.focus(); next.click(); } });
        });
      });
      all('.bt', root).forEach(group => group.addEventListener('click', event => {
        const button = event.target.closest('button'); if (!button) return;
        all('button',group).forEach(item=>item.classList.toggle('on',item===button));
        all('[data-m]',root).forEach(item=>{item.textContent=button.dataset.k==='y'?item.dataset.y:item.dataset.m;});
      }));
      all('.slots',root).forEach(group=>group.addEventListener('click',event=>{
        const button=event.target.closest('.slot'); if(!button)return;
        all('.slot',group).forEach(item=>{item.classList.toggle('on',item===button);item.setAttribute('aria-pressed',String(item===button));});
        const input=root.querySelector('input[name=time]');if(input)input.value=button.textContent;
      }));
      all('.chips[data-amt]',root).forEach(group=>group.addEventListener('click',event=>{
        const button=event.target.closest('.chip');if(!button)return;
        all('.chip',group).forEach(item=>item.classList.toggle('on',item===button));
        const input=root.getElementById('amt');if(input)input.value=button.dataset.v;
      }));
      const calc=root.getElementById('calc');
      if(calc){const run=()=>{const p=Number(root.getElementById('cp').value),d=Number(root.getElementById('cd').value)/100,r=Number(root.getElementById('cr').value)/1200,n=Number(root.getElementById('cy').value)*12,L=p*(1-d);const payment=r?L*r/(1-Math.pow(1+r,-n)):L/n;root.getElementById('cm').textContent=Number.isFinite(payment)&&payment>=0?'$'+Math.round(payment).toLocaleString()+'/mo':'Check the loan values';};calc.addEventListener('input',run);run();}
      all('form',root).forEach(form=>form.addEventListener('submit',async event=>{
        event.preventDefault(); if(form.dataset.preview==='true'||form.getAttribute('aria-busy')==='true'||!form.reportValidity())return;
        const status=form.querySelector('[role=status]'); form.setAttribute('aria-busy','true');
        try{const response=await fetch(form.action,{method:'POST',headers:{Accept:'application/json'},body:new FormData(form)});const result=await response.json();if(!response.ok)throw new Error(result.error||'Your request could not be saved. Please try again.');status.textContent=result.message+' Reference #'+result.reference;form.reset();}
        catch(error){status.textContent=error.message||'Your request could not be saved. Please try again.';}
        finally{form.removeAttribute('aria-busy');}
      }));
      const overlay = document.querySelector('[data-starter-lightbox]') || (()=>{const dialog=document.createElement('dialog');dialog.dataset.starterLightbox='';dialog.style.cssText='padding:16px;border:1px solid #777;border-radius:16px;max-width:90vw;background:#111;color:white';dialog.innerHTML='<button type="button" aria-label="Close image" style="display:block;margin-left:auto;padding:8px">Close ×</button><div data-image></div>';dialog.querySelector('button').addEventListener('click',()=>dialog.close());document.body.append(dialog);return dialog;})();
      all('.ph2',root).forEach(tile=>{tile.tabIndex=0;tile.setAttribute('role','button');tile.setAttribute('aria-label','View image');const show=()=>{const container=overlay.querySelector('[data-image]');container.replaceChildren();const image=tile.querySelector('img');if(image){const copy=image.cloneNode(true);copy.style.cssText='max-width:80vw;max-height:75vh;object-fit:contain';container.append(copy);}else{const placeholder=document.createElement('div');placeholder.style.cssText='width:70vw;height:65vh;background:'+getComputedStyle(tile).backgroundImage;container.append(placeholder);}overlay.showModal();};tile.addEventListener('click',show);tile.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();show();}});});
    });
  }
  document.addEventListener('DOMContentLoaded',mount);document.addEventListener('turbo:load',mount);mount();
})();
