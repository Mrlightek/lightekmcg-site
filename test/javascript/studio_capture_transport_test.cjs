// Run with Playwright installed: node test/javascript/studio_capture_transport_test.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require('playwright');
const scriptPath = process.env.STUDIO_JS || path.resolve('public/lightek/live/studio.js');
const html = `<main data-live-studio data-create-url="/sessions">
<video muted data-preview></video><div data-placeholder></div><span data-state></span><p data-status></p><p data-error hidden></p>
<button data-start>Start</button><button data-stop>Stop</button><button data-camera>Camera</button><button data-share>Screen</button><button data-mic>Mic</button><button data-hold>Hold</button><button data-release>Release</button>
<select data-camera-device><option value="">Default</option></select><select data-layout><option value="camera">Camera</option><option value="screen">Screen</option></select>
<select data-destination><option value="test">Test</option></select><input data-title value="Test"><a data-download hidden>Download</a><span data-source-status></span><span data-mic-status></span><meter data-meter></meter><span data-clock></span></main>`;
(async () => {
 const browser = await chromium.launch({headless:true, ...(process.env.CHROME_PATH ? {executablePath:process.env.CHROME_PATH}:{}), args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu','--autoplay-policy=no-user-gesture-required']});
 const context=await browser.newContext();
 try {
 async function fixture(mode) {
  const page=await context.newPage();
  await page.addInitScript(mode=>{
   window.received=[];window.stopCount=0;
   navigator.mediaDevices.getUserMedia=async()=>{const c=document.createElement('canvas');c.width=640;c.height=360;const ctx=c.getContext('2d');setInterval(()=>ctx.fillRect(0,0,640,360),40);return c.captureStream(24);};
   navigator.mediaDevices.enumerateDevices=async()=>[];
   class Recorder extends EventTarget {
    static isTypeSupported(){return true;}
    constructor(){super();window.rec=this;this.state='inactive';}
    start(){this.state='recording';}
    emit(size,offset=0){const data=Uint8Array.from({length:size},(_,i)=>(i+offset)%251);this.dispatchEvent(new MessageEvent('dataavailable',{data:new Blob([data])}));}
    stop(){this.state='inactive';if(mode==='burst')this.emit(111,1500000);this.dispatchEvent(new Event('stop'));}
   }
   window.MediaRecorder=Recorder;
   class Socket extends EventTarget {
    static OPEN=1;
    constructor(){super();window.socket=this;this.readyState=1;setTimeout(()=>this.deliver({type:'welcome'}),0);}
    deliver(packet){this.dispatchEvent(new MessageEvent('message',{data:JSON.stringify(packet)}));}
    send(raw){const msg=JSON.parse(raw);if(msg.command==='subscribe')return setTimeout(()=>this.deliver({type:'confirm_subscription'}),0);const data=JSON.parse(msg.data);
     if(data.action==='start')return setTimeout(()=>this.deliver({message:{event:'ready'}}),0);
     if(data.action==='chunk'){const bytes=Uint8Array.from(atob(data.live_chunk),c=>c.charCodeAt(0));window.received.push({sequence:data.sequence,size:bytes.length,valid:bytes.every((v,i)=>v===(window.received.reduce((n,x)=>n+x.size,0)+i)%251)});if(mode!=='noack')setTimeout(()=>this.deliver({message:{event:'ack',sequence:data.sequence}}),40);}
     if(data.action==='stop'){window.stopCount++;this.deliver({message:{event:'ended',download_url:'/recording'}});}
    }
    close(){this.readyState=3;}
   }
   window.WebSocket=Socket;
  },mode);
  await page.route('https://capture.test/**',route=>{const p=new URL(route.request().url()).pathname;return route.fulfill({contentType:p==='/studio.js'?'application/javascript':p==='/sessions'?'application/json':'text/html',body:p==='/studio.js'?fs.readFileSync(scriptPath):p==='/sessions'?JSON.stringify({ticket:'fixture',cable_path:'/cable'}):html+'<script src="/studio.js"></script>'});});
  await page.goto('https://capture.test/');await page.locator('[data-camera]').click();await page.locator('[data-start]').click();await page.waitForFunction(()=>window.rec?.state==='recording');return page;
 }
 let page=await fixture('burst');await page.evaluate(()=>{rec.emit(1500000);document.querySelector('[data-stop]').click();});
 await page.locator('[data-download]').waitFor({state:'visible',timeout:5000});
 const result=await page.evaluate(()=>({received,stopCount,error:document.querySelector('[data-error]').textContent}));
 assert.equal(result.error,'');assert.equal(result.stopCount,1);assert.equal(result.received.reduce((n,x)=>n+x.size,0),1500111);assert(result.received.length>1);result.received.forEach((x,i)=>{assert.equal(x.sequence,i);assert(x.size<=262144);assert(x.valid,'WebM bytes changed or reordered');});await page.close();
 page=await fixture('noack');await page.evaluate(()=>rec.emit(100));await page.locator('[data-error]').filter({hasText:'did not acknowledge'}).waitFor({timeout:15000});assert.equal(await page.locator('[data-start]').isDisabled(),false);await page.close();
 page=await fixture('overflow');await page.evaluate(()=>rec.emit(4194305));await page.locator('[data-error]').filter({hasText:'4 MB waiting'}).waitFor();assert.equal(await page.evaluate(()=>received.length),0);await page.close();
 console.log('STUDIO_CAPTURE_TRANSPORT_PASS large_burst byte_order bounded_chunks stop_drain missing_ack bounded_memory');
 } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
