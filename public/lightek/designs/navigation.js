(()=>{
 function start(){document.querySelectorAll('.lt-site-nav').forEach(nav=>{
  if(nav.dataset.dropdownsWired)return;nav.dataset.dropdownsWired='1';
  const branches=()=>[...nav.querySelectorAll('details.lt-nav-branch')];
  function closeAll(){branches().forEach(branch=>branch.open=false);}
  nav.addEventListener('toggle',event=>{const branch=event.target;if(!branch.matches('details.lt-nav-branch')||!branch.open)return;const siblings=branch.parentElement.parentElement;[...siblings.children].forEach(item=>{const other=item.querySelector(':scope > details.lt-nav-branch');if(other&&other!==branch)other.open=false;});},true);
  nav.addEventListener('keydown',event=>{if(event.key!=='Escape')return;const target=event.target.closest('details[open]')||branches().filter(branch=>branch.open).at(-1);if(!target)return;event.preventDefault();event.stopPropagation();target.open=false;target.querySelector(':scope > summary')?.focus();});
  nav.addEventListener('click',event=>{if(event.target.closest('a'))closeAll();});
  const outside=event=>{if(!nav.contains(event.target))closeAll();};document.addEventListener('pointerdown',outside);
  nav.addEventListener('focusout',()=>queueMicrotask(()=>{if(!nav.contains(document.activeElement))closeAll();}));
  document.addEventListener('turbo:before-cache',()=>{closeAll();document.removeEventListener('pointerdown',outside);delete nav.dataset.dropdownsWired;},{once:true});
 });}
 document.addEventListener('turbo:load',start);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
