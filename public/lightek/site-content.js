(()=>{
 if(window.LightekSiteContentWired)return;window.LightekSiteContentWired=true;
 const tags=['strong','em','h2','blockquote','p'];
 function insertNode(rich,node){const selection=getSelection();let range=selection.rangeCount?selection.getRangeAt(0):null;if(!range||!rich.contains(range.commonAncestorContainer)){range=document.createRange();range.selectNodeContents(rich);range.collapse(false);}range.deleteContents();range.insertNode(node);range.selectNodeContents(node);selection.removeAllRanges();selection.addRange(range);rich.dispatchEvent(new Event('input',{bubbles:true}));rich.focus();}
 document.addEventListener('mousedown',e=>{if(e.target.closest('[data-article-wrap]'))e.preventDefault();});
 document.addEventListener('click',e=>{const b=e.target.closest('[data-article-wrap]');if(!b||!tags.includes(b.dataset.articleWrap))return;const rich=b.closest('[data-article-editor]').querySelector('[data-article-rich]'),selection=getSelection(),node=document.createElement(b.dataset.articleWrap);if(selection.rangeCount&&rich.contains(selection.getRangeAt(0).commonAncestorContainer))node.append(selection.getRangeAt(0).cloneContents());if(!node.textContent)node.textContent='Your text';insertNode(rich,node);});
 document.addEventListener('paste',e=>{const rich=e.target.closest('[data-article-rich]');if(!rich)return;e.preventDefault();const fragment=document.createElement('span');const lines=e.clipboardData.getData('text/plain').slice(0,50000).split('\n');lines.forEach((text,i)=>{if(i)fragment.append(document.createElement('br'));fragment.append(document.createTextNode(text));});insertNode(rich,fragment);});
 document.addEventListener('input',e=>{
  const form=e.target.closest('[data-article-editor]');if(!form)return;
  if(e.target.matches('[data-article-rich]')){form.querySelector('[data-article-body]').value=e.target.innerHTML;return;}
  const slug=form.querySelector('[data-article-slug]');if(e.target===slug){slug.dataset.slugAuto='false';return;}
  if(e.target.name==='article[title]'&&slug.dataset.slugAuto==='true')slug.value=e.target.value.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'').slice(0,160).replace(/-$/,'');
 });
 document.addEventListener('change',e=>{if(!e.target.matches('[data-theme-files]'))return;const select=e.target.form.querySelector('[data-theme-home]'),old=select.value;select.replaceChildren(new Option('Detect index/home, then first file',''));for(const file of e.target.files)select.add(new Option(file.name,file.name));select.value=[...select.options].some(o=>o.value===old)?old:'';});
})();
