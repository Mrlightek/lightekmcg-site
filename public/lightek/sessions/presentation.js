export class SessionPresentation{
 constructor(){this.settings={layout:'gallery',background:'#142f2c',accent:'#d6edac',participants:{}};this.lastLayout='';this.changed=0;this.previous=null;}
 configure(settings){this.settings={...this.settings,...settings,participants:settings.participants||this.settings.participants};}
 paint(ctx,items,now=performance.now()){
 const s=this.settings,w=1280,h=720;ctx.save();ctx.filter='none';ctx.fillStyle=s.background;ctx.fillRect(0,0,w,h);const gradient=ctx.createLinearGradient(0,0,w,h);gradient.addColorStop(0,'rgba(255,255,255,.07)');gradient.addColorStop(1,'rgba(0,0,0,.45)');ctx.fillStyle=gradient;ctx.fillRect(0,0,w,h);
 ctx.fillStyle=s.accent;ctx.fillRect(40,36,5,50);ctx.fillStyle='#f5f7f2';ctx.font='600 27px system-ui';ctx.fillText(s.title||'Together, on Lightek',62,63,900);ctx.fillStyle='#c7d6cb';ctx.font='17px system-ui';ctx.fillText(s.subtitle||'A Lightek live experience',62,88,900);ctx.fillStyle=s.accent;ctx.font='600 16px system-ui';ctx.textAlign='right';ctx.fillText(s.brand||'LIGHTEK',1236,62,230);ctx.textAlign='left';
 const shown=items.slice(0,12),layout=items.some(item=>item.screen)&&s.layout==='gallery'?'presenter':s.layout;const featured=shown.find(item=>item.identity===s.featured)||shown.find(item=>item.screen)||shown[0];let boxes=[];
 if(layout==='fullscreen'&&featured)boxes=[[featured,40,115,1200,540]];
 else if(layout==='presenter'&&featured){boxes.push([featured,40,115,866,540]);shown.filter(item=>item!==featured).slice(0,3).forEach((item,i)=>boxes.push([item,926,115+i*184,314,172]));}
 else{const list=layout==='split'?shown.slice(0,2):shown,cols=list.length===1?1:list.length<=4?2:list.length<=9?3:4,rows=Math.ceil(Math.max(1,list.length)/cols),bw=(1200-18*(cols-1))/cols,bh=(540-18*(rows-1))/rows;list.forEach((item,i)=>boxes.push([item,40+(i%cols)*(bw+18),115+Math.floor(i/cols)*(bh+18),bw,bh]));}
 if(!boxes.length){ctx.fillStyle='#e3edda';ctx.font='32px system-ui';ctx.fillText('The conversation begins here.',60,375);}
 for(const [item,x,y,bw,bh] of boxes){const conf=s.participants[item.identity]||{};ctx.save();ctx.beginPath();if(ctx.roundRect)ctx.roundRect(x,y,bw,bh,14);else ctx.rect(x,y,bw,bh);ctx.clip();ctx.fillStyle='rgba(255,255,255,.065)';ctx.fillRect(x,y,bw,bh);const el=item.el;
 if(el?.readyState>=2&&!item.muted&&el.videoWidth&&el.videoHeight){const ratio=conf.fit==='cover'?Math.max(bw/el.videoWidth,bh/el.videoHeight):Math.min(bw/el.videoWidth,bh/el.videoHeight),vw=el.videoWidth*ratio,vh=el.videoHeight*ratio;ctx.filter={mono:'grayscale(1)',warm:'sepia(.25) saturate(1.15)',cool:'hue-rotate(12deg) saturate(.85)',soft:'blur(1px) contrast(.95)'}[conf.effect]||'none';if(conf.mirror){ctx.translate(x+bw,y);ctx.scale(-1,1);ctx.drawImage(el,(bw-vw)/2,(bh-vh)/2,vw,vh);}else ctx.drawImage(el,x+(bw-vw)/2,y+(bh-vh)/2,vw,vh);ctx.filter='none';}
 else{ctx.fillStyle=s.accent;ctx.font='600 '+Math.round(Math.min(75,bh*.35))+'px system-ui';ctx.textAlign='center';ctx.fillText((conf.name||item.name||'Guest').split(' ').map(v=>v[0]).slice(0,2).join('').toUpperCase(),x+bw/2,y+bh/2, bw-30);ctx.textAlign='left';}
 ctx.fillStyle='rgba(4,17,18,.85)';ctx.fillRect(x,y+bh-54,bw,54);ctx.fillStyle=s.accent;ctx.fillRect(x,y+bh-54,4,54);ctx.fillStyle='#fff';ctx.font='600 '+Math.min(21,Math.max(14,bw/20))+'px system-ui';ctx.fillText(conf.name||item.name||'Guest',x+15,y+bh-(conf.role?29:18),bw-30);if(conf.role){ctx.fillStyle='#d1ddcf';ctx.font='14px system-ui';ctx.fillText(conf.role,x+15,y+bh-10,bw-30);}ctx.restore();}
 if(s.ticker){ctx.fillStyle=s.accent;ctx.fillRect(0,678,w,42);ctx.fillStyle='#142924';ctx.font='600 18px system-ui';const text=s.ticker+'     •     ',length=ctx.measureText(text).width;let x=-(now*.055%length);while(x<w){ctx.fillText(text,x,705);x+=length;}}
 ctx.restore();
 }
}
