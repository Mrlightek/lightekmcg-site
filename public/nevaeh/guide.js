if(window.self!==window.top)document.documentElement.classList.add('ng-embedded');
const topics=document.querySelector('.ng-topics');
if(topics){const wide=matchMedia('(min-width:901px)');const layout=()=>{topics.open=wide.matches;};layout();wide.addEventListener('change',layout);}
for(const pre of document.querySelectorAll('.ng-card pre')){
  const button=document.createElement('button');button.type='button';button.className='ng-copy';button.textContent='Copy';
  button.addEventListener('click',async()=>{const text=pre.querySelector('code')?.textContent||'';try{await navigator.clipboard.writeText(text);button.textContent='Copied';}catch{button.textContent='Select text to copy';}setTimeout(()=>button.textContent='Copy',2000);});
  pre.prepend(button);
}
