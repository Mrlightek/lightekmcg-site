const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');const {chromium}=require('playwright');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH,args:['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
try{const page=await browser.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
await page.route('https://depth.test/**',route=>{const url=new URL(route.request().url());if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><div id="host" style="width:64px;height:64px"></div>'});const file=path.join('public',url.pathname);return route.fulfill({body:fs.readFileSync(file),contentType:'application/javascript'});});await page.goto('https://depth.test');
const result=await page.evaluate(async()=>{
 const THREE=await import('/lightek/vendor/three/three.module.js'),{createServerDepthLayer}=await import('/lightek/spatial/server-depth.js');
 const renderer=new THREE.WebGLRenderer({preserveDrawingBuffer:true});renderer.setSize(64,64);renderer.outputColorSpace=THREE.SRGBColorSpace;document.querySelector('#host').append(renderer.domElement);
 const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(45,1,.02,100);camera.position.z=.6;camera.updateMatrixWorld();camera.updateProjectionMatrix();
 const canvas=document.createElement('canvas');canvas.width=2;canvas.height=1;const context=canvas.getContext('2d');context.fillStyle='red';context.fillRect(0,0,2,1);const bitmap=await createImageBitmap(canvas,{imageOrientation:'flipY'});
 const layer=createServerDepthLayer();scene.add(layer.mesh);
 layer.update({bitmap,depthValues:new Float32Array([.1,.99999]),width:2,height:1,colorFrameId:'one',depthFrameId:'one',camera,projectionMatrix:camera.projectionMatrix.toArray(),viewMatrix:camera.matrixWorldInverse.toArray()});
 const person=new THREE.Mesh(new THREE.PlaneGeometry(.5,.5),new THREE.MeshBasicMaterial({color:0x00ff00}));scene.add(person);renderer.render(scene,camera);
 const gl=renderer.getContext(),left=new Uint8Array(4),right=new Uint8Array(4);gl.readPixels(16,32,1,1,gl.RGBA,gl.UNSIGNED_BYTE,left);gl.readPixels(48,32,1,1,gl.RGBA,gl.UNSIGNED_BYTE,right);
 let rejected=false;try{layer.update({bitmap,depthValues:new Float32Array([.5]),width:1,height:1,colorFrameId:'one',depthFrameId:'two',camera});}catch{rejected=true;}
 layer.dispose();person.geometry.dispose();person.material.dispose();renderer.dispose();return {left:Array.from(left),right:Array.from(right),rejected};
});assert(result.left[0]>200&&result.left[1]<20,JSON.stringify(result));assert(result.right[1]>200&&result.right[0]<20,JSON.stringify(result));assert(result.rejected);assert.deepEqual(errors,[]);console.log('STUDIO_SPATIAL_DEPTH_PASS server_front person_front unmatched_frame_rejected',JSON.stringify(result));
}finally{await browser.close();}})().catch(error=>{console.error(error);process.exitCode=1;});
