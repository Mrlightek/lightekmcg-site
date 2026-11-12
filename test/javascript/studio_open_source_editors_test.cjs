// Real upstream editors + real Rails controllers/storage/workers over stdio.
const {spawn,execFileSync}=require('child_process'),fs=require('fs'),path=require('path'),readline=require('readline'),http=require('http'),assert=require('assert/strict');
const {chromium}=require('playwright');const repo=path.resolve(__dirname,'../..');
const proof=process.env.STUDIO_EDITOR_PROOF_DIR||path.join(repo,'tmp/open-source-editors');fs.mkdirSync(proof,{recursive:true});
const ruby=process.env.STUDIO_TEST_RUBY||'ruby';
const child=spawn(ruby,['test/standalone/studio_editors_checks.rb'],{cwd:repo,env:{...process.env,MT_NO_PLUGINS:'1',STUDIO_EDITOR_RPC:'1'},stdio:['pipe','pipe','pipe']});
let readyResolve,pending=null,logs='';const ready=new Promise(resolve=>readyResolve=resolve);let chain=Promise.resolve();
readline.createInterface({input:child.stdout}).on('line',line=>{let value;try{value=JSON.parse(line);}catch{return;}if(value.ready)return readyResolve(value);if(pending){const callback=pending;pending=null;value.error?callback.reject(Error(JSON.stringify(value))):callback.resolve(value);}});
child.stderr.on('data',data=>logs+=data.toString());
function rpc(data){const promise=chain.then(()=>new Promise((resolve,reject)=>{pending={resolve,reject};child.stdin.write(JSON.stringify(data)+'\n');}));chain=promise.catch(()=>{});return promise;}
function makeMedia(){
  execFileSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=0x28a5b3:s=320x180:d=2:r=30','-f','lavfi','-i','sine=frequency=440:duration=2','-c:v','libvpx','-threads','1','-c:a','libvorbis',path.join(proof,'source.webm')]);
  execFileSync('ffmpeg',['-hide_banner','-loglevel','error','-y','-f','lavfi','-i','color=c=0xe7b456:s=240x160','-frames:v','1','-threads','1',path.join(proof,'source.png')]);
}
(async()=>{
  let browser,page,server;
  try{
    makeMedia();console.log('Preparing real Rails fixture');const context=await Promise.race([ready,new Promise((_,reject)=>setTimeout(()=>reject(Error('Rails fixture failed to start: '+logs)),30000))]);
    console.log('Rails fixture ready',context);browser=await chromium.launch({headless:true,args:['--no-sandbox','--no-zygote','--single-process','--use-gl=angle','--use-angle=swiftshader']});
    page=await browser.newPage({viewport:{width:1440,height:1000}});const errors=[],failures=[];page.on("requestfailed",request=>console.log("REQUEST FAILED",request.url(),request.failure()));page.on('pageerror',error=>errors.push(error.message));
    server=http.createServer(async(request,response)=>{
      try{
        const url=new URL(request.url,'http://localhost');
        if(url.pathname.startsWith('/lightek/')){
          const file=path.join(repo,'public',url.pathname);
          if(!fs.existsSync(file)){failures.push(url.pathname);response.writeHead(404);return response.end();}
          const type={'.js':'application/javascript','.css':'text/css','.html':'text/html','.svg':'image/svg+xml','.ttf':'font/ttf','.png':'image/png'}[path.extname(file)]||'application/octet-stream';
          response.writeHead(200,{'content-type':type});return response.end(fs.readFileSync(file));
        }
        if(url.pathname==='/favicon.ico'){response.writeHead(204);return response.end();}
        const chunks=[];for await(const chunk of request)chunks.push(chunk);
        const result=await rpc({method:request.method,path:request.url,headers:request.headers,body:Buffer.concat(chunks).toString('base64')});
        if(url.pathname.startsWith('/dashboard/studio/editors/'))console.log('HTTP',request.method,url.pathname,result.status);
        const headers={...result.headers};delete headers['transfer-encoding'];delete headers['content-encoding'];
        response.writeHead(result.status,headers);response.end(Buffer.from(result.body,'base64'));
      }catch(error){console.error(error);response.writeHead(500);response.end(error.message);}
    });
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const origin=`http://127.0.0.1:${server.address().port}`;
    await page.route('https://**',route=>route.abort());
    await page.goto(`${origin}/dashboard/studio/editors/photo/new?site_id=${context.site_id}`);
    await page.getByLabel('Project name').fill('Monday launch poster');await page.getByRole('button',{name:'Open Photo Studio'}).click();
    await page.waitForFunction(()=>document.querySelector('[data-editor-ready="true"]')&&window.LightekEditors?.photo?.FileSave);await page.locator('[data-editor-import]').setInputFiles(path.join(proof,'source.png'));
    await page.waitForFunction(()=>window.LightekEditors.photo.AppConfig.layers.some(layer=>layer.name==='source.png'&&layer.link?.complete));
    await page.frameLocator('#lightek-photo-editor').getByTitle('Duplicate layer',{exact:true}).click();
    await page.waitForFunction(()=>LightekEditors.photo.AppConfig.layers.length>=2);
    await page.getByRole('button',{name:'Save project',exact:true}).click();await page.getByRole('status').filter({hasText:'Project saved to Lightek'}).waitFor();
    console.log('Photo saved');const photoURL=page.url();await page.reload();await page.waitForFunction(()=>window.LightekEditors?.photo?.AppConfig.layers.some(layer=>layer.name==='source.png'&&layer.link?.complete));
    assert.equal(await page.evaluate(()=>LightekEditors.photo.AppConfig.WIDTH),1920);assert(await page.evaluate(()=>LightekEditors.photo.AppConfig.layers.length>=2));
    await page.getByRole('button',{name:'Export PNG',exact:true}).click();await page.waitForFunction(()=>document.querySelector('[data-editor-exports] [data-operation]'));
    await rpc({jobs:true});await page.getByRole('link',{name:/Download .*\.png/}).waitFor({timeout:20000});
    const png=await page.request.get(new URL(await page.getByRole('link',{name:/Download .*\.png/}).getAttribute('href'),page.url()).href);assert.equal(png.status(),200);fs.writeFileSync(path.join(proof,'export.png'),await png.body());
    const [backup]=await Promise.all([page.waitForEvent('download'),page.getByRole('button',{name:'Download project backup',exact:true}).click()]);await backup.saveAs(path.join(proof,'photo-backup.json'));
    await page.locator('[data-editor-restore]').setInputFiles(path.join(proof,'photo-backup.json'));await page.waitForFunction(()=>document.querySelector('[data-editor-ready="true"]')&&window.LightekEditors?.photo?.AppConfig.layers.length>=2);
    await page.screenshot({path:path.join(proof,'photo-desktop.png'),fullPage:true});
    await page.goto(`${origin}/dashboard/studio/editors/video/new?site_id=${context.site_id}`);await page.getByLabel('Project name').fill('Monday launch video');await page.getByRole('button',{name:'Open Video Studio'}).click();
    await page.waitForFunction(()=>document.querySelector('[data-editor-ready="true"]')&&window.LightekEditors?.editor?.selection?.mash);
    await page.locator('[data-editor-import]').setInputFiles(path.join(proof,'source.webm'));
    await page.waitForFunction(()=>window.LightekEditors?.editor?.selection?.mash?.tracks.some(track=>track.clips.length>0),{timeout:30000});
    await page.locator('.timeline .clip').first().click();
    await page.locator('.inspector input[name=label]').fill('Opening cut');await page.keyboard.press('Tab');
    await page.getByRole('button',{name:'Save project',exact:true}).click();await page.getByRole('status').filter({hasText:'Project saved to Lightek'}).waitFor();
    console.log('Video saved');const videoURL=page.url();await page.reload();await page.waitForFunction(()=>window.LightekEditors?.editor?.selection?.mash?.tracks.some(track=>track.clips.length>0));
    const reopened=JSON.stringify(await page.evaluate(()=>LightekEditors.snapshot()));assert.match(reopened,/lightek\.media\./);assert.match(reopened,/Opening cut/);
    await page.getByRole('button',{name:'Export MP4',exact:true}).click();await page.waitForFunction(()=>document.querySelector('[data-editor-exports] [data-operation]'));
    await rpc({jobs:true});await page.getByRole('link',{name:/Download .*\.mp4/}).waitFor({timeout:20000});
    const mp4=await page.request.get(new URL(await page.getByRole('link',{name:/Download .*\.mp4/}).getAttribute('href'),page.url()).href);assert.equal(mp4.status(),200);fs.writeFileSync(path.join(proof,'export.mp4'),await mp4.body());
    const metadata=JSON.parse(execFileSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',path.join(proof,'export.mp4')],{encoding:'utf8'}));assert(metadata.streams.some(stream=>stream.codec_name==='h264'));assert(metadata.streams.some(stream=>stream.codec_type==='audio'));assert(Math.abs(Number(metadata.format.duration)-2)<0.2);
    for(const width of [1440,1024,390]){await page.setViewportSize({width,height:1000});await page.screenshot({path:path.join(proof,`video-${width}.png`),fullPage:true});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),`Video overflow at ${width}`);for(const selector of ['.panel.player','.panel.timeline','.panel.inspector']){const panel=page.locator('#lightek-video-editor '+selector);assert(await panel.isVisible());const rect=await panel.boundingBox();assert(rect.x>=0&&rect.x+rect.width<=width+1,`${selector} is clipped at ${width}`);}}
    await page.goto(photoURL);await page.waitForFunction(()=>document.querySelector('[data-editor-ready="true"]')&&window.LightekEditors?.photo?.FileSave);await page.screenshot({path:path.join(proof,'photo-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[],'Browser JavaScript errors');assert.deepEqual(failures,[],'Missing local editor assets');
    console.log('OPEN_SOURCE_EDITORS_PASS actual miniPaint/Movie Masher: import, save, reopen, PNG/MP4 export, media-library persistence, 1440/1024/390; real Rails/ActiveStorage/FFmpeg');
  }catch(error){if(page){console.log('FAILED URL',page.url());fs.writeFileSync(path.join(proof,'failed.html'),await page.content());await page.screenshot({path:path.join(proof,'failed.png'),fullPage:true});}console.error(logs.slice(-4000));throw error;}finally{await browser?.close();server?.close();child.stdin.end();child.kill('SIGTERM');}
})().catch(error=>{console.error(error);process.exitCode=1;});
