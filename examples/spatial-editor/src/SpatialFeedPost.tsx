import {useEffect,useRef,useState} from 'react';
export type SpatialPost={id:string;flatUrl:string;posterUrl:string;manifestUrl?:string;title:string;interactive:boolean};
export type FeedStage={setEye:(x:number,y:number,z:number)=>void;resize:()=>void;dispose:()=>void};
/** loadStage must build actual scene geometry/rigs, not merely pan a flat video. */
export function SpatialFeedPost({post,loadStage}:{post:SpatialPost;loadStage:(host:HTMLElement,manifestUrl:string)=>Promise<FeedStage>}){
  const host=useRef<HTMLDivElement>(null),video=useRef<HTMLVideoElement>(null),stage=useRef<FeedStage|null>(null),active=useRef(false),orientation=useRef({x:0,y:0});
  const [motion,setMotion]=useState(false),[status,setStatus]=useState('Move the pointer to look around');
  useEffect(()=>{const node=host.current;if(!node)return;let disposed=false,token=0,raf=0,current={x:0,y:0};
    const pointer=(event:PointerEvent)=>{if(event.pointerType==='touch')return;const r=node.getBoundingClientRect();orientation.current={x:Math.max(-1,Math.min(1,2*(event.clientX-r.left)/r.width-1)),y:Math.max(-1,Math.min(1,1-2*(event.clientY-r.top)/r.height))};};
    const reset=()=>{orientation.current={x:0,y:0};};
    const observer=new IntersectionObserver(async entries=>{const visible=entries[0].intersectionRatio>=.6&&document.visibilityState==='visible';active.current=visible;const attempt=++token;
      if(!visible){video.current?.pause();stage.current?.dispose();stage.current=null;return;}
      await video.current?.play().catch(()=>{});
      if(post.interactive&&post.manifestUrl&&!matchMedia('(prefers-reduced-motion: reduce)').matches){
        try{const loaded=await loadStage(node,post.manifestUrl);if(disposed||attempt!==token){loaded.dispose();return;}stage.current=loaded;}
        catch{if(!disposed)setStatus('Flat playback · spatial assets could not load');}
      }
    },{threshold:[0,.6,1]});observer.observe(node);
    const hidden=()=>{if(document.visibilityState!=='visible'){active.current=false;video.current?.pause();stage.current?.dispose();stage.current=null;++token;}else{observer.unobserve(node);observer.observe(node);}};
    const resize=new ResizeObserver(()=>stage.current?.resize());resize.observe(node);
    const draw=()=>{if(disposed)return;if(active.current){current.x+=(orientation.current.x-current.x)*.12;current.y+=(orientation.current.y-current.y)*.12;stage.current?.setEye(current.x*.035,current.y*.025,.6);}raf=requestAnimationFrame(draw);};draw();
    node.addEventListener('pointermove',pointer);node.addEventListener('pointerleave',reset);document.addEventListener('visibilitychange',hidden);
    return()=>{disposed=true;++token;active.current=false;cancelAnimationFrame(raf);observer.disconnect();resize.disconnect();node.removeEventListener('pointermove',pointer);node.removeEventListener('pointerleave',reset);document.removeEventListener('visibilitychange',hidden);stage.current?.dispose();stage.current=null;};
  },[post.id,post.flatUrl,post.manifestUrl,post.interactive,loadStage]);
  useEffect(()=>{if(!motion)return;let center:{beta:number;gamma:number}|null=null;
    const move=(event:DeviceOrientationEvent)=>{if(!active.current||event.beta===null||event.gamma===null)return;center??={beta:event.beta,gamma:event.gamma};const angle=screen.orientation?.angle||0,x=(event.gamma-center.gamma)/20,y=(event.beta-center.beta)/20,r=angle*Math.PI/180;orientation.current={x:Math.max(-1,Math.min(1,x*Math.cos(r)+y*Math.sin(r))),y:Math.max(-1,Math.min(1,-x*Math.sin(r)+y*Math.cos(r)))};};
    window.addEventListener('deviceorientation',move);return()=>window.removeEventListener('deviceorientation',move);
  },[motion]);
  const enableMotion=async()=>{try{const ctor=DeviceOrientationEvent as typeof DeviceOrientationEvent&{requestPermission?:()=>Promise<string>};if(ctor.requestPermission&&await ctor.requestPermission()!=='granted')throw Error('Motion permission denied');setMotion(true);setStatus('Tilt gently to look around');}catch{setStatus('Motion unavailable · pointer and flat video remain available');}};
  return <article aria-label={post.title}><div ref={host} style={{position:'relative',aspectRatio:'9 / 16',overflow:'hidden'}}><video ref={video} src={post.flatUrl} poster={post.posterUrl} muted loop playsInline controls style={{width:'100%',height:'100%',objectFit:'contain'}}/></div><p>{post.title}</p>{post.interactive&&<button onClick={()=>motion?setMotion(false):void enableMotion()}>{motion?'Stop motion view':'Enable motion view'}</button>}<p role="status">{status}</p></article>;
}
