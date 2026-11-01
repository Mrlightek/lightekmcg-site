const assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const {chromium}=require('playwright');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'live-library-'));
function generate(name,args){const file=path.join(root,name),result=spawnSync('ffmpeg',['-v','error','-y',...args,'-threads','1',file]);assert.equal(result.status,0,result.stderr.toString());return fs.readFileSync(file);}
const video=generate('program.mp4',['-f','lavfi','-i','color=c=blue:s=160x90:r=24','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','4','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart']);
const audio=generate('bed.wav',['-f','lavfi','-i','sine=frequency=110:sample_rate=48000','-t','1']);
const image=generate('overlay.png',['-f','lavfi','-i','color=c=green:s=16x16','-frames:v','1']);
const html=`<main data-live-studio data-create-url="/sessions"><video muted data-preview></video><div data-placeholder></div><span data-state></span><p data-status></p><p data-error hidden></p>
<button data-start>Start</button><button data-stop>Stop</button><button data-camera>Camera</button><button data-share>Screen</button><button data-mic>Mic</button><button data-hold>Hold</button><button data-release>Release</button><select data-camera-device><option value="">Default</option></select><select data-layout><option value="camera">Camera</option><option value="screen">Screen</option><option value="library">Library</option></select><select data-destination><option value="test">Test</option></select><input data-title value="Library test"><a data-download hidden>Download</a><span data-source-status></span><span data-mic-status></span><meter data-meter></meter><span data-clock></span>
<select data-library-visual><option value="">None</option><option value="1" data-kind="video" data-library-url="/api/lightek/pwa/assets/1/proxy">Program clip</option><option value="4" data-kind="image" data-library-url="/api/lightek/pwa/assets/3/proxy">Still image</option><option value="5" data-kind="video" data-library-url="/api/lightek/pwa/assets/5/proxy">Broken clip</option></select><input type="checkbox" data-library-loop checked>
<select data-library-overlay><option value="">None</option><option value="3" data-library-url="/api/lightek/pwa/assets/3/proxy">Graphic</option></select><select data-library-audio><option value="">None</option><option value="2" data-library-url="/api/lightek/pwa/assets/2/proxy">Audio bed</option></select><input type="range" data-library-volume min="0" max="1" step="0.05" value="0.25"><button data-load-library>Load</button><button data-clear-library>Clear</button><p data-library-status></p></main><script src="/studio.js"></script>`;
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROME_PATH?{executablePath:process.env.CHROME_PATH}:{}),args:['--no-sandbox','--no-zygote','--single-process','--disable-gpu','--autoplay-policy=no-user-gesture-required']});
 try{
  const page=await browser.newPage();let sessions=0;const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
   const capture=HTMLCanvasElement.prototype.captureStream;HTMLCanvasElement.prototype.captureStream=function(...args){window.programCanvas=this;return capture.apply(this,args);};
   window.gainNodes=[];const original=AudioContext.prototype.createGain;AudioContext.prototype.createGain=function(){const node=original.call(this);gainNodes.push(node);return node;};
   window.chunks=0;
   class Socket extends EventTarget{static OPEN=1;constructor(){super();this.readyState=1;setTimeout(()=>this.deliver({type:'welcome'}),0);}deliver(packet){this.dispatchEvent(new MessageEvent('message',{data:JSON.stringify(packet)}));}send(raw){const message=JSON.parse(raw);if(message.command==='subscribe')return setTimeout(()=>this.deliver({type:'confirm_subscription'}),0);const data=JSON.parse(message.data);if(data.action==='start')return setTimeout(()=>this.deliver({message:{event:'ready'}}),0);if(data.action==='chunk'){chunks++;return setTimeout(()=>this.deliver({message:{event:'ack',sequence:data.sequence}}),0);}if(data.action==='stop')return setTimeout(()=>this.deliver({message:{event:'ended'}}),0);}close(){this.readyState=3;}}
   window.WebSocket=Socket;
  });
  await page.route('https://capture.test/**',route=>{const url=new URL(route.request().url()).pathname;if(url==='/sessions'){sessions++;return route.fulfill({contentType:'application/json',body:JSON.stringify({ticket:'test',cable_path:'/cable'})});}if(url.endsWith('/1/proxy'))return route.fulfill({contentType:'video/mp4',body:video});if(url.endsWith('/2/proxy'))return route.fulfill({contentType:'audio/wav',body:audio});if(url.endsWith('/3/proxy'))return route.fulfill({contentType:'image/png',body:image});if(url.endsWith('/5/proxy'))return route.fulfill({status:404,body:'Missing'});return route.fulfill({contentType:url==='/studio.js'?'application/javascript':'text/html',body:url==='/studio.js'?fs.readFileSync('public/lightek/live/studio.js'):html});});
  await page.goto('https://capture.test/');await page.selectOption('[data-layout]','library');await page.click('[data-start]');assert.match(await page.locator('[data-error]').textContent(),/Load a library/);assert.equal(sessions,0);
  await page.selectOption('[data-library-visual]','1');await page.selectOption('[data-library-audio]','2');await page.click('[data-load-library]');await page.locator('[data-library-status]').filter({hasText:'Library media loaded'}).waitFor();assert.equal(sessions,0);assert.equal(await page.inputValue('[data-layout]'),'library');
  assert.deepEqual(await page.evaluate(()=>gainNodes.map(node=>node.gain.value)),[0,1,0.25]);
  await page.waitForFunction(()=>{const pixel=programCanvas.getContext('2d').getImageData(640,360,1,1).data;return pixel[2]>200&&pixel[0]<10;});
  await page.click('[data-hold]');assert.deepEqual(await page.evaluate(()=>gainNodes.map(node=>node.gain.value)),[0,0,0]);await page.click('[data-hold]');assert.deepEqual(await page.evaluate(()=>gainNodes.map(node=>node.gain.value)),[0,1,0.25]);
  await page.click('[data-start]');await page.waitForFunction(()=>chunks>0);assert.equal(sessions,1);await page.click('[data-stop]');await page.locator('[data-status]').filter({hasText:'Session ended.'}).waitFor();
  await page.selectOption('[data-library-visual]','4');await page.selectOption('[data-library-overlay]','3');await page.click('[data-load-library]');await page.locator('[data-library-status]').filter({hasText:'Library media loaded'}).waitFor();
  assert.equal(await page.inputValue('[data-layout]'),'library');await page.waitForFunction(()=>{const pixel=programCanvas.getContext('2d').getImageData(640,360,1,1).data;return pixel[1]>100&&pixel[2]<10;});await page.click('[data-clear-library]');assert.match(await page.locator('[data-library-status]').textContent(),/cleared/);
  await page.selectOption('[data-library-visual]','5');await page.click('[data-load-library]');await page.locator('[data-error]').filter({hasText:'cannot be decoded'}).waitFor();
  await page.click('[data-release]');assert.equal(await page.locator('[data-placeholder]').evaluate(element=>element.hidden),false);assert.deepEqual(errors,[]);
  console.log('STUDIO_LIVE_LIBRARY_PASS actual_mp4_png_wav program overlay audio_mix holding_mute private_capture decode_error cleanup');
 }finally{await browser.close();fs.rmSync(root,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
