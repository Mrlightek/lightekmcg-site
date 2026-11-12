import React from 'react';
import {createRoot} from 'react-dom/client';
import {Masher, MasherDefaultProps, MasherContext} from '@moviemasher/client-react';
import * as Core from '@moviemasher/moviemasher.js';
function Bridge({ready}) {
  const {editor}=React.useContext(MasherContext);
  React.useEffect(()=>{if(editor)ready(editor);},[editor]);
  return null;
}
window.LightekMovieMasher={Core,mount(element,document,ready){
  const aspect=(document.mash.width||1280)/(document.mash.height||720);
  const preview=()=>{const available=element.clientWidth;const width=Math.min(480,Math.max(220,available>850?available-520:available-60));const height=Math.min(360,width/aspect);return {width:Math.round(height*aspect),height:Math.round(height)};};
  const props=MasherDefaultProps({edited:document,previewSize:preview(),panels:{player:{header:{content:[React.createElement('strong',{key:'label'},'Program preview')]}}}});
  props.children=[...React.Children.toArray(props.children),React.createElement(Bridge,{key:'lightek',ready})];
  const root=createRoot(element);root.render(React.createElement(Masher,props));
  const observer=new ResizeObserver(()=>{const surface=element.querySelector('.editor');if(!surface)return;const size=preview();surface.style.setProperty('--preview-width',`${size.width}px`);surface.style.setProperty('--preview-height',`${size.height}px`);surface.style.setProperty('--preview-aspect-ratio',String(aspect));});observer.observe(element);
  return ()=>{observer.disconnect();root.unmount();};
}};
