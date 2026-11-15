/* Operator-selected chat graphics in the existing captured program canvas. */
(()=>{
 const sources={lightek:'Lightek',room:'Session',tiktok:'TikTok',ssn:'Social Stream Ninja'};
 const clean=(value,max)=>{const text=Array.from(String(value??'').replace(/[\u0000-\u001f\u007f]/g,' ').replace(/\s+/g,' ').trim());return text.length>max?text.slice(0,max-1).join('')+'…':text.join('');};
 class CommentGraphic {
  constructor(changed=()=>{}){this.changed=changed;this.selected=null;this.wrapped=null;}
  show(value){if(!value||!Object.hasOwn(sources,value.source))throw Error('Choose a supported audience comment.');const text=clean(value.text,320);if(!text)throw Error('Choose a comment with text.');this.selected={source:value.source,platform:value.source==='ssn'?clean(value.platform,24):'',name:clean(value.name,80)||'Viewer',text};this.wrapped=null;this.changed(this.selected);}
  clear(){this.selected=null;this.wrapped=null;this.changed(null);}
  label(){return this.selected?this.selected.platform||sources[this.selected.source]:'';}
  wrap(ctx,text,width){const lines=[];let line='';for(const char of Array.from(text)){if(ctx.measureText(line+char).width>width&&line){lines.push(line.trimEnd());line=char===' '?'':char;}else line+=char;}if(line)lines.push(line.trimEnd());const result=lines.slice(0,3);if(lines.length>3){let last=result[2];while(last&&ctx.measureText(last+'…').width>width)last=Array.from(last).slice(0,-1).join('');result[2]=last.trimEnd()+'…';}return result;}
  draw(ctx,accent='#d6edac'){
   if(!this.selected)return;ctx.save();ctx.filter='none';ctx.globalAlpha=1;ctx.textAlign='left';ctx.textBaseline='alphabetic';ctx.font='500 28px system-ui';this.wrapped ||= this.wrap(ctx,this.selected.text,1152);const height=64+32*this.wrapped.length,x=40,y=662-height;
   ctx.fillStyle='rgba(11,18,27,.95)';ctx.fillRect(x,y,1200,height);ctx.fillStyle=/^#[a-fA-F0-9]{6}$/.test(accent)?accent:'#d6edac';ctx.fillRect(x,y,5,height);ctx.font='600 19px system-ui';ctx.fillText(this.label()+' · '+this.selected.name,x+24,y+30,1152);ctx.fillStyle='#f5f7f2';ctx.font='500 28px system-ui';this.wrapped.forEach((line,index)=>ctx.fillText(line,x+24,y+64+32*index,1152));ctx.restore();
  }
 }
 function boot(root){const host=root.querySelector('[data-comment-control]');if(!host)return null;const preview=host.querySelector('[data-comment-preview]'),status=host.querySelector('[data-comment-status]'),clear=host.querySelector('[data-comment-clear]');const graphic=new CommentGraphic(selected=>{preview.textContent=selected?graphic.label()+' · '+selected.name+': '+selected.text:'';preview.hidden=!selected;clear.disabled=!selected;status.textContent=selected?'Selected for the program. Review the preview; all chosen broadcast destinations receive this graphic.':'No comment selected.';});root.addEventListener('lightek:feature-comment',event=>{try{graphic.show(event.detail);}catch(error){status.textContent=error.message;}});clear.addEventListener('click',()=>graphic.clear());graphic.clear();return graphic;}
 window.LightekLiveComments={CommentGraphic,boot};
})();
