for(const pre of document.querySelectorAll('.ng-card pre')){
  const button=document.createElement('button');button.type='button';button.className='ng-copy';button.textContent='Copy';
  button.addEventListener('click',async()=>{const text=pre.querySelector('code')?.textContent||'';try{await navigator.clipboard.writeText(text);button.textContent='Copied';}catch{button.textContent='Select text to copy';}setTimeout(()=>button.textContent='Copy',2000);});
  pre.prepend(button);
}
