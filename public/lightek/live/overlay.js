/* Graphic placement uses the same program canvas captured for recording/broadcast. */
(()=>{
 const defaults={enabled:true,x:0,y:0,width:1280,height:720,opacity:1,fit:'stretch'};
 const bounds={x:[-1280,1280],y:[-720,720],width:[1,1280],height:[1,720],opacity:[0,1]};
 function normalize(raw={}){
  if(!raw||typeof raw!=='object'||Array.isArray(raw)||Object.keys(raw).some(key=>!Object.hasOwn(defaults,key)))throw Error('Unsupported graphic placement fields.');
  const config={...defaults,...raw};if(typeof config.enabled!=='boolean')throw Error('Graphic visibility must be on or off.');
  if(!['stretch','contain'].includes(config.fit))throw Error('Choose stretch or preserve aspect ratio.');
  for(const [key,[min,max]] of Object.entries(bounds))if(typeof config[key]!=='number'||!Number.isFinite(config[key])||config[key]<min||config[key]>max)throw Error(`Graphic ${key} must be between ${min} and ${max}.`);
  return config;
 }
 function draw(ctx,image,raw){
  const c=normalize(raw);if(!c.enabled||c.opacity===0||!image?.complete||!(image.naturalWidth>0)||!(image.naturalHeight>0))return false;
  let width=c.width,height=c.height;if(c.fit==='contain'){const scale=Math.min(c.width/image.naturalWidth,c.height/image.naturalHeight);width=image.naturalWidth*scale;height=image.naturalHeight*scale;}
  ctx.save();try{ctx.globalAlpha=c.opacity;ctx.drawImage(image,c.x+(c.width-width)/2,c.y+(c.height-height)/2,width,height);}finally{ctx.restore();}return true;
 }
 function boot(root){
  const host=root.querySelector('[data-overlay-controls]');if(!host)return null;const q=s=>host.querySelector(s),notice=q('[data-overlay-status]');let state={...defaults},error='';
  const controls=[...host.querySelectorAll('[data-overlay-field]')];
  function apply(raw){const config=normalize(raw);state=config;error='';for(const el of controls){const key=el.dataset.overlayField;if(el.type==='checkbox')el.checked=config[key];else el.value=String(config[key]);}notice.textContent='Graphic placement ready · load a graphic and review the program preview.';}
  function changed(){try{const values={};for(const el of controls){const key=el.dataset.overlayField;if(el.type==='checkbox')values[key]=el.checked;else if(key==='fit')values[key]=el.value;else{if(el.value.trim()==='')throw Error('Set all graphic placement values before saving.');values[key]=Number(el.value);}}state=normalize(values);error='';notice.textContent='Graphic placement updated in the program preview. Save the production setup to reuse it.';}catch(e){error=e.message;notice.textContent=error+' Preview keeps the last valid placement.';}}
  host.addEventListener('input',changed);host.addEventListener('change',changed);q('[data-overlay-reset]').addEventListener('click',()=>apply(defaults));apply(defaults);
  return {read:()=>{if(error)throw Error(error);return {...state};},apply,draw:(ctx,image)=>draw(ctx,image,state)};
 }
 window.LightekLiveOverlay={normalize,draw,defaults:()=>({...defaults}),boot};
})();
