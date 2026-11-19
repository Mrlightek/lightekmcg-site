export const motionPresets=[['sway','Sway'],['float','Float'],['drift_left','Drift left'],['drift_right','Drift right']];
export function motionPreset(name,amount=.02,duration=3){
  const points={sway:[[0,0,0],[.25,amount,0],[.75,-amount,0],[1,0,0]],float:[[0,0,0],[.5,0,-amount],[1,0,0]],drift_left:[[0,0,0],[1,-amount,0]],drift_right:[[0,0,0],[1,amount,0]]}[name];
  if(!points)throw Error('Choose an installed motion preset.');
  return {duration,loop:['sway','float'].includes(name),keyframes:points.map(([t,x,y])=>({t,x,y}))};
}
export function transformMotion(motion,width,height,scale,rotation){
  const angle=rotation*Math.PI/180;
  return {...motion,keyframes:motion.keyframes.map(point=>{
    const x=point.x*width*scale,y=point.y*height*scale;
    return {...point,x:x*Math.cos(angle)-y*Math.sin(angle),y:x*Math.sin(angle)+y*Math.cos(angle)};
  })};
}
export function motionOffset(motion,time){
  const t=motion.loop?(time%motion.duration)/motion.duration:Math.min(Math.max(time/motion.duration,0),1);
  const index=motion.keyframes.findIndex((point,index)=>index>0&&t<=point.t);
  const a=motion.keyframes[index-1],b=motion.keyframes[index],blend=(t-a.t)/(b.t-a.t);
  return [a.x+(b.x-a.x)*blend,a.y+(b.y-a.y)*blend];
}
