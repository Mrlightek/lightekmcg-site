const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader']});
 try{
  const page=await browser.newPage();page.on('console',message=>{if(process.env.STUDIO_VISION_DEBUG)console.log('VISION',message.text().slice(0,300));});
  await page.context().route('**/*',route=>{
   const url=new URL(route.request().url());let file;
   if(url.pathname==='/')return route.fulfill({contentType:'text/html',body:'<!doctype html><title>Real MediaPipe model verification</title>'});
   if(url.pathname==='/worker.js')file='public/lightek/spatial/vision-worker.js';
   else file=path.join(process.env.STUDIO_VISION_CACHE||'/tmp/lightek-spatial-runtime',url.pathname.split('/').at(-1));
   if(!fs.existsSync(file))throw Error('Missing runtime fixture '+file);
   return route.fulfill({contentType:file.endsWith('.mjs')||file.endsWith('.js')?'application/javascript':file.endsWith('.wasm')?'application/wasm':file.endsWith('.jpg')?'image/jpeg':'application/octet-stream',headers:{'access-control-allow-origin':'*'},body:fs.readFileSync(file)});
  });
  await page.goto('https://vision.test/');
  const result=await page.evaluate(()=>new Promise(async(resolve,reject)=>{
   const worker=new Worker('/worker.js');const messages=[];
   const timeout=setTimeout(()=>{worker.terminate();reject(Error('Real vision worker timed out '+JSON.stringify(messages)));},60000);
   const sendFrame=async time=>{const bitmap=await createImageBitmap(await(await fetch('/portrait.jpg')).blob());worker.postMessage({type:'frame',time,bitmap,segment:true},[bitmap]);};
   worker.onerror=event=>{clearTimeout(timeout);worker.terminate();reject(Error(event.message));};
   worker.onmessage=async({data})=>{
    messages.push({type:data.type,message:data.message});
    if(data.type==='error'){clearTimeout(timeout);worker.terminate();reject(Error(data.message));}
    if(data.type==='ready')worker.postMessage({type:'segment'});
    if(data.type==='segment-ready')await sendFrame(1000);
    if(data.type==='result'){clearTimeout(timeout);worker.terminate();resolve({landmarks:data.landmarks?.length,mask:data.mask?{width:data.mask.width,height:data.mask.height,min:data.mask.bytes.reduce((a,b)=>Math.min(a,b),255),max:data.mask.bytes.reduce((a,b)=>Math.max(a,b),0)}:null});}
   };
   worker.postMessage({type:'init'});
  }));
  assert(result.landmarks>=468);assert(result.mask?.width>0);assert(result.mask.min<.2&&result.mask.max>.8);
  console.log('STUDIO_SPATIAL_VISION_PASS real_mediapipe_wasm face_landmarks foreground_confidence_mask worker_inference',JSON.stringify(result));
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
