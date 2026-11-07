"""Mandatory CI desktop transport proof. Requires Docker and Playwright, no mock VNC."""
import base64, hashlib, hmac, importlib.util, json, os, pathlib, subprocess, tempfile, threading, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('gateway',ROOT/'lib/scripts/studio_workstation_gateway.py')
gateway=importlib.util.module_from_spec(spec);spec.loader.exec_module(gateway)

@unittest.skipUnless(os.environ.get('LIGHTEK_TEST_WORKSTATION')=='1','Docker desktop acceptance is enabled in CI')
class DesktopAcceptance(unittest.TestCase):
    def test_real_desktop_connect_switch_save_and_revoke(self):
        def run(*args):return subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()
        image=os.environ.get('STUDIO_WORKSTATION_IMAGE','lightek/studio-workstation:20261107')
        with tempfile.TemporaryDirectory(prefix='lightek-desktop-') as temp:
            root=pathlib.Path(temp);key='a'*32;session=root/'sessions'/key;work=session/'work';work.mkdir(parents=True)
            run('blender','--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python-expr',f"import bpy; bpy.ops.wm.save_as_mainfile(filepath={str(work/'scene.blend')!r})")
            container=run('docker','run','-d','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--pids-limit','512','--memory','4g','--cpus','2','--shm-size','512m','--user',f'{os.getuid()}:{os.getgid()}','--tmpfs','/tmp:rw,nosuid,size=1g','--mount',f'type=bind,source={work},target=/work','--mount',f'type=bind,source={ROOT}/blender,target=/engine,readonly',image)
            server=None
            try:
                run('docker','cp',container+':/usr/share/novnc',str(root/'novnc'))
                for attempt in range(90):
                    if (work/'.desktop.sock').exists():
                        result=subprocess.run(['docker','exec','-e','DISPLAY=:99',container,'xdotool','search','--onlyvisible','--class','Blender'],capture_output=True)
                        if result.returncode==0:break
                    time.sleep(1)
                else:self.fail('Native desktop did not start: '+run('docker','logs',container))
                server=gateway.GatewayServer(('127.0.0.1',0),gateway.GatewayHandler)
                server.root=root;server.static=root/'novnc';server.secret=b's'*64
                origin=f'http://127.0.0.1:{server.server_port}'
                manifest={'session_key':key,'owner_id':1,'status':'ready','container_id':container,'origin':origin,'expires_at':int(time.time())+600}
                (session/'session.json').write_text(json.dumps(manifest))
                threading.Thread(target=server.serve_forever,daemon=True).start()
                payload=base64.urlsafe_b64encode(json.dumps({'sid':key,'uid':1,'exp':manifest['expires_at']}).encode()).decode().rstrip('=')
                signature=base64.urlsafe_b64encode(hmac.new(server.secret,payload.encode(),hashlib.sha256).digest()).decode().rstrip('=')
                url=origin+f'/studio-workstations/{key}/bootstrap?ticket={payload}.{signature}'
                script="""const {chromium}=require('playwright');(async()=>{const b=await chromium.launch({headless:true,args:['--no-sandbox']});try{const p=await b.newPage();await p.goto(process.env.DESKTOP_URL);await p.waitForFunction(()=>document.querySelector('#noVNC_status')?.textContent.includes('Connected'),{},{timeout:60000});const c=p.locator('#noVNC_container canvas');await c.waitFor();const visible=await c.evaluate(c=>{const d=c.getContext('2d').getImageData(0,0,c.width,c.height).data;let n=0;for(let i=0;i<d.length;i+=400)if(d[i]+d[i+1]+d[i+2]>30)n++;return c.width>500&&c.height>300&&n>100});if(!visible)throw Error('No native desktop pixels');await p.screenshot({path:process.env.DESKTOP_SCREENSHOT});console.log('Native Blender pixels over authenticated Unix WebSocket verified');}finally{await b.close()}})().catch(e=>{console.error(e);process.exit(1)});"""
                env=dict(os.environ,DESKTOP_URL=url,DESKTOP_SCREENSHOT=str(ROOT/'tmp/workstation-desktop.png'));(ROOT/'tmp').mkdir(exist_ok=True)
                run_result=subprocess.run(['node','-e',script],env=env,text=True,capture_output=True,timeout=90)
                self.assertEqual(run_result.returncode,0,run_result.stdout+run_result.stderr)
                run('docker','exec','-e','DISPLAY=:99',container,'xdotool','key','ctrl+alt+4')
                nonce='0123456789abcdef';(work/'.studio-save-request.json').write_text(json.dumps({'nonce':nonce}))
                run('docker','exec','-e','DISPLAY=:99',container,'xdotool','key','F8')
                receipt=work/'.studio-save-receipt.json'
                for attempt in range(30):
                    if receipt.exists():break
                    time.sleep(1)
                self.assertTrue(receipt.exists(),'Native F8 save receipt missing')
                data=json.loads(receipt.read_text());self.assertEqual(data['nonce'],nonce)
                self.assertEqual(data['sha256'],hashlib.sha256((work/'scene.blend').read_bytes()).hexdigest())
                self.assertTrue((work/'project.zip').exists())
                manifest['status']='stopped';(session/'session.json').write_text(json.dumps(manifest))
                with self.assertRaises(PermissionError):gateway.verify_ticket(payload+'.'+signature,server.secret,manifest)
            finally:
                if server:server.shutdown();server.server_close()
                subprocess.run(['docker','rm','-f',container],capture_output=True)
