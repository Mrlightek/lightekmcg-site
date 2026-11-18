import React,{useEffect,useState} from 'react';
import {requestKey} from './api';

export function sceneNodes(nodes,ancestors=[]){
  return nodes.flatMap(node=>[{node,path:[...ancestors,node.id]},...(node.children?sceneNodes(node.children,[...ancestors,node.id]):[])]);
}
export function editSceneNode(graph,id,changes){
  const visit=nodes=>nodes.map(node=>node.id===id?{...node,...changes}:node.children?{...node,children:visit(node.children)}:node);
  return {...graph,nodes:visit(graph.nodes)};
}
export function flattenScene(graph){
  const {width,height}=graph.canvas;const output=[];
  function visit(nodes,x=0,y=0,scale=1,rotation=0,depth=0,opacity=1){
    [...nodes].map((node,index)=>({node,index})).sort((a,b)=>(a.node.z_index||0)-(b.node.z_index||0)||a.index-b.index).forEach(({node})=>{
      const angle=rotation*Math.PI/180,dx=(node.x||0)*width*scale,dy=(node.y||0)*height*scale;
      const nx=x+dx*Math.cos(angle)-dy*Math.sin(angle),ny=y+dx*Math.sin(angle)+dy*Math.cos(angle);
      const nr=rotation+(node.rotation||0),nd=node.depth??depth,alpha=opacity*(node.opacity??1);
      if(node.children)visit(node.children,nx,ny,scale*(node.scale||1),nr,nd,alpha);
      else output.push({...node,x:nx,y:ny,width:node.width*width*scale,height:node.height*height*scale,rotation:nr,depth:nd,opacity:alpha});
    });
  }
  visit(graph.nodes);return output;
}
function ScenePreview({composition,catalog,assets}){
  if(!composition)return <div className="ls-card"><p>Your scene layout and live parallax preview appear here.</p></div>;
  const {width,height,duration}=composition.canvas;
  return <svg className="ls-layered-preview" role="img" aria-label="Live 2D parallax scene preview" viewBox={`0 0 ${width} ${height}`}>
    <rect width={width} height={height} fill="#121820"/>
    {flattenScene(composition).map(layer=>{
      const src=layer.template?catalog.find(asset=>asset.key===layer.template)?.url:assets.find(asset=>asset.id===layer.asset_id)?.proxy_url;
      const dx=-composition.camera.x*width*layer.depth,dy=-composition.camera.y*height*layer.depth;
      return src&&<g key={layer.id} opacity={layer.opacity} data-layer-id={layer.id} data-layer-depth={layer.depth}>
        <animateTransform attributeName="transform" type="translate" values={`0 0;${dx} ${dy};0 0`} dur={`${duration*2}s`} repeatCount="indefinite"/>
        <image href={src} x={layer.x-layer.width/2} y={layer.y-layer.height/2} width={layer.width} height={layer.height}
          transform={`rotate(${layer.rotation} ${layer.x} ${layer.y})`} preserveAspectRatio={layer.fit==='cover'?'xMidYMid slice':layer.fit==='contain'?'xMidYMid meet':'none'}/>
      </g>;
    })}
  </svg>;
}
export function LayeredComposer({api,scene,assets,composition,update,prompt,setPrompt,onReady,onSaved,run,busy}){
  const [status,setStatus]=useState(null),[attempt,setAttempt]=useState(0),[error,setError]=useState('');
  const [selected,setSelected]=useState(''),[newAsset,setNewAsset]=useState('tree.oak'),[seed,setSeed]=useState('');
  useEffect(()=>{
    let alive=true;onReady(false);
    api.call('workflow.status',{scene_id:scene.id}).then(result=>{if(alive){setStatus(result);onReady(!!result.ready);}}).catch(()=>{if(alive){setStatus({ready:false,message:'Studio could not check its 2D compositor. Recheck the worker connection.'});onReady(false);}});
    return()=>{alive=false;};
  },[api,scene.id,attempt]);
  const catalog=status?.assets||[];
  const records=composition?sceneNodes(composition.nodes):[];
  const selectedRecord=records.find(item=>item.node.id===selected);
  const current=selectedRecord?.node;
  const effectiveDepth=selectedRecord?.path.reduce((depth,id)=>records.find(item=>item.node.id===id).node.depth??depth,0)??0;
  const images=assets.filter(asset=>asset.kind==='image'&&asset.status==='ready'&&asset.proxy_url);
  const perform=action=>run(async()=>{setError('');try{await action();}catch(cause){setError(cause.message);}});
  const field=(name,label,min,max,step=1,percent=false)=><label key={name}>{label}<input type="number" min={min} max={max} step={step} value={percent?Math.round((current[name]??0)*10000)/100:current[name]??(name==='depth'?effectiveDepth:1)} onChange={event=>update(editSceneNode(composition,current.id,{[name]:Number(event.target.value)/(percent?100:1)}))}/></label>;
  function add(){
    if(records.filter(item=>!item.node.children).length>=24){setError('This scene supports up to 24 image layers.');return;}
    const id='layer-'+requestKey();
    const source=newAsset.startsWith('image:')?{asset_id:Number(newAsset.slice(6)),fit:'contain'}:{template:newAsset,fit:'stretch'};
    update({...composition,nodes:[...composition.nodes,{id,name:newAsset,...source,x:.5,y:.5,width:.25,height:.4,z_index:50,depth:.6,rotation:0,opacity:1}]});setSelected(id);
  }
  return <section className="ls-layered" aria-label="2D scene composer">
    <p className="ls-muted">Build a scene from reusable image assets, then animate its layers with depth and camera movement.</p>
    <label>Scene prompt<textarea rows="3" maxLength="300" required={!composition} value={prompt} onChange={event=>setPrompt(event.target.value)} placeholder="A nighttime park with a character sitting on a bench"/></label>
    <div className="ls-row"><label>Seed for new layout<input type="number" min="0" max="4294967295" value={seed} placeholder="Random variation" onChange={event=>setSeed(event.target.value)}/></label>
      <button type="button" disabled={busy||!prompt.trim()} onClick={()=>perform(async()=>{
        const result=await api.call('workflow.plan',{scene_id:scene.id,prompt:prompt.trim(),...(seed!==''?{seed:Number(seed)}:{})});update(result.composition);setSelected('');
      })}>Generate layout</button>
      <button type="button" disabled={busy} onClick={()=>setAttempt(value=>value+1)}>Recheck 2D worker</button>
    </div>
    {status&&<p role="status" className={status.ready?'ls-muted':'ls-error'}>{status.message}</p>}
    <ScenePreview {...{composition,catalog,assets}}/>
    {composition&&<>
      <p className="ls-muted">Seed {composition.seed} · {records.filter(item=>!item.node.children).length} layers. Layer order controls stacking; depth controls parallax speed. The preview loops forward and back; export follows the camera move once.</p>
      <div className="ls-fields">
        <label>Output size<select value={`${composition.canvas.width}x${composition.canvas.height}`} onChange={event=>{const [width,height]=event.target.value.split('x').map(Number);update({...composition,canvas:{...composition.canvas,width,height}});}}>
          <option value="640x360">640 × 360</option><option value="1280x720">1280 × 720</option><option value="1920x1080">1920 × 1080</option><option value="1080x1920">1080 × 1920</option><option value="1080x1080">1080 × 1080</option>
        </select></label>
        <label>Duration (seconds)<input type="number" min="1" max="10" step=".5" value={composition.canvas.duration} onChange={event=>update({...composition,canvas:{...composition.canvas,duration:Number(event.target.value)}})}/></label>
        <label>Camera move X (%)<input type="number" min="-30" max="30" step="1" value={Math.round(composition.camera.x*100)} onChange={event=>update({...composition,camera:{...composition.camera,x:Number(event.target.value)/100}})}/></label>
        <label>Camera move Y (%)<input type="number" min="-30" max="30" step="1" value={Math.round(composition.camera.y*100)} onChange={event=>update({...composition,camera:{...composition.camera,y:Number(event.target.value)/100}})}/></label>
      </div>
      <div className="ls-row"><label>Asset or group<select value={selected} onChange={event=>setSelected(event.target.value)}><option value="">Select a layer to edit</option>{records.map(({node,path})=><option key={node.id} value={node.id}>{'· '.repeat(path.length-1)}{node.name||node.id}{node.children?' (group)':''}</option>)}</select></label>
        <button type="button" disabled={busy} onClick={()=>perform(async()=>{const result=await api.call('workflow.save',{scene_id:scene.id,lock_version:scene.lock_version,composition});update(result.composition);onSaved(result);})}>Save scene layers</button>
      </div>
      {current&&<div className="ls-card ls-fields" aria-label="Selected layer controls">
        {field('z_index','Layer order (z-index)',-10000,10000)}{field('depth','Parallax depth',0,1,.05)}
        {field('x','X position (%)',-200,200,1,true)}{field('y','Y position (%)',-200,200,1,true)}
        {field('rotation','Rotation',-180,180)}{field('opacity','Opacity',0,1,.05)}
        {current.children?field('scale','Group scale',.1,2,.1):<>{field('width','Width (%)',1,200,1,true)}{field('height','Height (%)',1,200,1,true)}
          <label>Image fit<select value={current.fit||'stretch'} onChange={event=>update(editSceneNode(composition,current.id,{fit:event.target.value}))}><option value="contain">Contain</option><option value="cover">Cover</option><option value="stretch">Stretch</option></select></label></>}
        <button type="button" onClick={()=>{const remove=nodes=>nodes.filter(node=>node.id!==current.id).map(node=>node.children?{...node,children:remove(node.children)}:node);update({...composition,nodes:remove(composition.nodes)});setSelected('');}}>Remove selected layer or group</button>
      </div>}
      <div className="ls-row"><label>Add an asset<select value={newAsset} onChange={event=>setNewAsset(event.target.value)}>{catalog.map(asset=><option key={asset.key} value={asset.key}>{asset.name}</option>)}{images.map(asset=><option key={asset.id} value={'image:'+asset.id}>{asset.name} (your image)</option>)}</select></label><button type="button" disabled={busy} onClick={add}>Add layer</button></div>
    </>}
    {error&&<p role="alert" className="ls-error">{error}</p>}
  </section>;
}
