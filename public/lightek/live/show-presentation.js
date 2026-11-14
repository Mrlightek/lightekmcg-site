/* Portable show styling is separate from room participants and admission state. */
(()=>{
 const defaults={layout:'gallery',title:'',subtitle:'',brand:'',ticker:'',background:'#142f2c',accent:'#d6edac'};
 const clone=value=>JSON.parse(JSON.stringify(value));
 class ShowPresentation {
  constructor(){this.override=null;}
  portable(values={}){return Object.fromEntries(Object.entries(defaults).map(([key,fallback])=>[key,values[key]??fallback]));}
  forRoom(settings={}){return {...this.portable(settings),...clone(settings),...(this.override||{})};}
  apply(values,current={}){this.override=this.portable(values);return this.forRoom(current);}
  edited(values){if(this.override)this.override=this.portable(values);}
  restore(settings={}){this.override=null;return {...this.portable(settings),...clone(settings)};}
 }
 window.LightekLiveShowPresentation=ShowPresentation;
})();
