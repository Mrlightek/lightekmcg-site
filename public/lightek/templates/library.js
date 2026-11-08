(() => {
  function start(){document.querySelectorAll('[data-template-library]').forEach(root=>{
    if(root.dataset.wired)return;root.dataset.wired='true';
    const search=root.querySelector('[data-template-search]'),filters=root.querySelectorAll('[data-template-filter]'),cards=root.querySelectorAll('[data-template-card]');let category='all';
    const filter=()=>{const query=search.value.trim().toLocaleLowerCase();let count=0;cards.forEach(card=>{const show=(category==='all'||category===card.dataset.category)&&card.dataset.search.includes(query);card.hidden=!show;if(show)count++;});root.querySelector('[data-template-count]').textContent=count+' designs';root.querySelector('[data-template-empty]').hidden=count!==0;};
    search.addEventListener('input',filter);filters.forEach(button=>button.addEventListener('click',()=>{category=button.dataset.templateFilter;filters.forEach(item=>item.setAttribute('aria-pressed',String(item===button)));filter();}));filter();
  });}
  document.addEventListener('DOMContentLoaded',start);document.addEventListener('turbo:load',start);start();
})();
