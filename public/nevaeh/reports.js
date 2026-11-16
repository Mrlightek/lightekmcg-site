/* Per-specialist operational experience and owner feedback, beside the work. */
(()=>{
  const node=(tag,text)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;return e;};
  let root,select,list,notice,signature='',loading=false;
  function field(label,input){const row=node('label');row.className='workforce-field';row.append(node('span',label),input);return row;}
  function render(data){
    const next=JSON.stringify(data);if(next===signature)return;
    // Preserve feedback being composed during background refreshes.
    if(list.contains(document.activeElement))return;
    signature=next;list.replaceChildren();
    list.append(node('p',data.scope),node('p',data.learning));
    for(const report of data.reports||[]){
      const card=node('article');card.className='workforce-card';
      card.append(node('h3','#'+report.id+' · '+report.agent),node('p',report.capability+' · '+report.status+' · application '+report.site));
      card.append(node('p',report.review?'Owner review: '+report.review.verdict:'No current owner review. Service completion does not establish output quality.'));
      if(report.review?.lesson)card.append(node('p',report.review.lesson));
      if(report.review_history?.length){const history=node('details');history.append(node('summary','Review history ('+report.review_count+' total; latest 10)'));for(const review of report.review_history)history.append(node('p',review.created_at+' · '+review.verdict+': '+review.lesson));card.append(history);}
      if(report.structured_report){const structured=node('details');structured.append(node('summary','Worker JSON report · schema v'+report.structured_report.schema_version),node('pre',JSON.stringify(report.structured_report,null,2)));card.append(structured);}
      const evidence=node('details');evidence.append(node('summary','Execution evidence and references'),node('pre',JSON.stringify(report.evidence,null,2)));card.append(evidence);
      if(report.evidence.action_id){const link=node('a','Open actual execution receipt');link.href='/dashboard/nevaeh/actions/'+report.evidence.action_id;link.target='_blank';link.rel='noopener';card.append(link);}
      if(report.status!=='pending'){
        const details=node('details');details.append(node('summary','Review result or teach this specialist'));
        const form=node('form'),verdict=node('select');verdict.setAttribute('aria-label','Review verdict for report '+report.id);
        const options=report.status==='completed'?['accepted','needs_fix','rejected','withdrawn']:['needs_fix','rejected','withdrawn'];
        for(const value of options)verdict.add(new Option(value.replaceAll('_',' '),value));
        const lesson=node('textarea');lesson.rows=3;lesson.maxLength=2000;lesson.placeholder='What should this specialist repeat or change next time?';lesson.value=report.review?.lesson||'';
        const save=node('button','Save review');save.type='submit';save.className='btn primary';
        const status=node('p');status.setAttribute('role','status');
        form.append(field('Result assessment',verdict),field('Lesson or correction',lesson),save,status);details.append(form);card.append(details);
        form.onsubmit=async event=>{
          event.preventDefault();save.disabled=true;status.textContent='Saving owner feedback…';
          try{await api('/worker_reports/'+report.id+'/reviews','POST',{verdict:verdict.value,lesson:lesson.value,receipt_sha256:report.receipt_sha256});signature='';status.textContent='Saved. This feedback is available for matching specialist work.';lesson.blur();await refresh();}
          catch(error){status.textContent=error.message;}finally{save.disabled=false;}
        };
      }
      list.append(card);
    }
    if(!data.reports?.length)list.append(node('p','No worker reports yet. Delegate a task to begin this specialist’s operating history.'));
  }
  async function refresh(){if(!root?.isConnected||loading)return;loading=true;try{render(await api('/worker_reports'+(select.value?'?agent_id='+encodeURIComponent(select.value):'')));notice.textContent='';}catch(error){notice.textContent=error.message;}finally{loading=false;}}
  window.NevaehReports={mount(target,roles){
    if(!root){root=node('section');root.className='workforce-reports';root.append(node('h2','SME reports & lessons'),node('p','Each specialist accumulates its own evidence. Nevaeh retrieves matching reports and owner feedback before delegation.'));
      select=node('select');select.setAttribute('aria-label','Filter reports by specialist');select.add(new Option('All specialists',''));select.onchange=()=>{signature='';refresh();};root.append(field('Specialist',select));
      const button=node('button','Refresh reports');button.type='button';button.className='btn';button.onclick=refresh;notice=node('p');notice.setAttribute('role','status');list=node('div');root.append(button,notice,list);
    }
    const selected=select.value;select.replaceChildren(new Option('All specialists',''));for(const role of roles||[])select.add(new Option(role.name,String(role.id)));select.value=selected;
    if(root.parentNode!==target){target.replaceChildren(root);refresh();}
  },refresh};
  setInterval(()=>{if(root?.isConnected&&!document.hidden)refresh();},15000);
})();
