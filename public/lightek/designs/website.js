(()=>{
 function start(){
  const root=document.querySelector('[data-lightek-website]');if(!root||root.dataset.wired)return;root.dataset.wired='1';
  function fitHeadlines(){root.querySelectorAll('.hero__headline,.hero__title').forEach(heading=>{heading.style.fontSize='';const words=[...heading.querySelectorAll('.hero__headline-word,.hero__title-word')];const widest=Math.max(0,...words.map(word=>word.getBoundingClientRect().width));const available=heading.clientWidth;if(widest>available&&available>0)heading.style.fontSize=Math.floor(parseFloat(getComputedStyle(heading).fontSize)*available/widest*.98)+'px';});}
  document.fonts.ready.then(fitHeadlines);document.fonts.addEventListener('loadingdone',fitHeadlines);window.addEventListener('resize',fitHeadlines);
  const button=root.querySelector('[data-design-menu]'),links=root.querySelector('.nav__links');
  function close(){links?.classList.remove('is-open');button?.setAttribute('aria-expanded','false');button?.setAttribute('aria-label','Open navigation');}
  button?.addEventListener('click',()=>{const open=button.getAttribute('aria-expanded')!=='true';links?.classList.toggle('is-open',open);button.setAttribute('aria-expanded',String(open));button.setAttribute('aria-label',open?'Close navigation':'Open navigation');if(open)links?.querySelector('a')?.focus();});
  links?.querySelectorAll('a').forEach(link=>link.addEventListener('click',close));
  root.addEventListener('keydown',event=>{if(event.key==='Escape'&&button?.getAttribute('aria-expanded')==='true'){close();button.focus();}if(event.key==='Tab'&&button?.getAttribute('aria-expanded')==='true'){const elements=[...links.querySelectorAll('a,summary')].filter(element=>element.getClientRects().length).concat(button);const index=elements.indexOf(document.activeElement);if(event.shiftKey&&index===0){event.preventDefault();button.focus();}else if(!event.shiftKey&&document.activeElement===button){event.preventDefault();elements[0]?.focus();}}});
  const resize=new ResizeObserver(()=>{if(innerWidth>900)close();});resize.observe(root);
  document.addEventListener('turbo:before-cache',()=>{close();resize.disconnect();window.removeEventListener('resize',fitHeadlines);document.fonts.removeEventListener('loadingdone',fitHeadlines);delete root.dataset.wired;},{once:true});
 }
 document.addEventListener('turbo:load',start);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
})();
