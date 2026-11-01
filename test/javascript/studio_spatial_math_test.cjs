const assert=require('node:assert/strict'),fs=require('node:fs');
(async()=>{
 const {windowFrustum,HeadPose,faceMeasurement}=await import('data:text/javascript;base64,'+Buffer.from(fs.readFileSync('public/lightek/spatial/projection.js','utf8')).toString('base64'));
 const near=.02,width=.5,height=.3;
 for(const eye of [{x:0,y:0,z:.6},{x:.15,y:-.1,z:.4},{x:-.2,y:.2,z:1.2}]){
  const f=windowFrustum(eye,width,height,near,100);
  // Every screen-plane edge lands on the same NDC edge, independent of eye translation.
  const ndcX=x=>2*near/(f.right-f.left)*(x-eye.x)/eye.z-(f.right+f.left)/(f.right-f.left);
  const ndcY=y=>2*near/(f.top-f.bottom)*(y-eye.y)/eye.z-(f.top+f.bottom)/(f.top-f.bottom);
  assert(Math.abs(ndcX(-width/2)+1)<1e-10);assert(Math.abs(ndcX(width/2)-1)<1e-10);
  assert(Math.abs(ndcY(-height/2)+1)<1e-10);assert(Math.abs(ndcY(height/2)-1)<1e-10);
 }
 assert.throws(()=>windowFrustum({x:0,y:0,z:0},width,height));assert.throws(()=>windowFrustum({x:NaN,y:0,z:1},width,height));
 const pose=new HeadPose();pose.calibrate({x:.5,y:.5,span:.2});
 assert.equal(pose.estimate({x:.5,y:.5,span:.4},4/3).z,.3);
 assert(pose.estimate({x:.6,y:.5,span:.2},4/3).x<0);assert(pose.estimate({x:.5,y:.4,span:.2},4/3).y>0);
 assert.equal(faceMeasurement([]),null);assert.throws(()=>pose.calibrate(null));
 const moved=pose.smooth({x:.2,y:0,z:.6},.016);assert(moved.x>0&&moved.x<.2);
 console.log('STUDIO_SPATIAL_MATH_PASS fixed_window_edges head_calibration depth_ratio smoothing invalid_pose');
})().catch(error=>{console.error(error);process.exitCode=1;});
