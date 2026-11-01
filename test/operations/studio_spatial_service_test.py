"""Real persistent Blender + H.264 + WebRTC loopback, not a mocked video track.
Run with SPATIAL_TEST_BLENDER=/path/to/blender PYTHONPATH=<deps>:$PWD python ...
"""
import asyncio,json,os,tempfile,time,unittest
from pathlib import Path
from aiohttp import web,ClientSession
from aiortc import RTCPeerConnection,RTCConfiguration,RTCSessionDescription
from services.spatial.server import SpatialService,verify,ticket
from services.spatial.protocol import parse_message

SECRET='test-only-secret-at-least-thirty-two-characters'
class ProtocolTests(unittest.TestCase):
    def test_tickets(self):
        claims={'sid':'a','uid':1,'exp':time.time()+60};self.assertEqual(verify(SECRET,ticket(SECRET,claims)),claims)
        with self.assertRaises(ValueError):verify(SECRET,ticket(SECRET,{'exp':0}))
        with self.assertRaises(ValueError):verify(SECRET,ticket('wrong',claims))
    def test_invalid_commands(self):
        with self.assertRaises(ValueError):parse_message('{"type":"UNSAFE"}')
        with self.assertRaises(ValueError):parse_message('{"x":NaN}')

class LoopbackTests(unittest.IsolatedAsyncioTestCase):
    @unittest.skipUnless(os.environ.get('SPATIAL_TEST_BLENDER'),'Set SPATIAL_TEST_BLENDER for real Blender integration')
    async def test_changed_scene_reaches_webrtc(self):
        # This sandbox denies getifaddrs; explicit loopback still exercises real ICE/DTLS/SRTP.
        import aioice.ice
        aioice.ice.get_host_addresses=lambda **kwargs:['127.0.0.1']
        os.environ['SPATIAL_RENDER_ENGINE']='CYCLES';os.environ['SPATIAL_WIDTH']='160';os.environ['SPATIAL_HEIGHT']='90'
        with tempfile.TemporaryDirectory() as directory:
            async def commit(session,message):return message['scene_revision']+1
            service=SpatialService(root=directory,secret=SECRET,blender=os.environ['SPATIAL_TEST_BLENDER'],commit_callback=commit)
            runner=web.AppRunner(service.app());await runner.setup();site=web.TCPSite(runner,'127.0.0.1',0);await site.start()
            url='http://127.0.0.1:'+str(site._server.sockets[0].getsockname()[1]);peer=RTCPeerConnection(RTCConfiguration(iceServers=[]))
            try:
                async with ClientSession() as http:
                    manifest={'schema_version':'1.0','revision':0,'scene':{'id':1,'name':'RTC proof','settings':{'fps':24,'frame_start':1,'frame_end':250},'objects':[{'id':1,'name':'Cube','type':'cube','definition':{'location':[0,0,1],'scale':[1,1,1]}}]},'outputs':{}}
                    async with http.post(url+'/sessions',headers={'Authorization':'Bearer '+SECRET},json={'user_id':1,'origin':'https://studio.test','manifest':manifest}) as response:
                        self.assertEqual(response.status,201,await response.text());credentials=await response.json()
                    sid=credentials['session_id'];seq=0
                    def message(kind,payload):
                        nonlocal seq;seq+=1
                        return {'v':1,'type':kind,'session_id':sid,'message_id':str(seq),'seq':seq,'scene_revision':0,'payload':payload}
                    frames=asyncio.Queue();metadata=asyncio.Queue();pongs=asyncio.Queue();frame_acks=asyncio.Queue()
                    @peer.on('track')
                    def track_received(track):
                        async def receive():
                            while True:await frames.put(await track.recv())
                        self.receiver=asyncio.create_task(receive())
                    peer.addTransceiver('video',direction='recvonly');channel=peer.createDataChannel('telemetry')
                    @channel.on('message')
                    def received(value):
                        event=json.loads(value)
                        if event['type']=='FRAME_META':metadata.put_nowait(event)
                        if event['type']=='PONG':pongs.put_nowait(event)
                        if event['type']=='FRAME_ACK':frame_acks.put_nowait(event)
                    async with http.ws_connect(url+'/ws',headers={'Origin':'https://wrong.test'}) as denied:
                        await denied.send_json(message('HELLO',{'ticket':credentials['ticket'],'client_id':'denied','known_server_epoch':None}))
                        await denied.receive();self.assertEqual(denied.close_code,1008)
                    async with http.ws_connect(url+'/ws',headers={'Origin':'https://studio.test'}) as ws:
                        await ws.send_json(message('HELLO',{'ticket':credentials['ticket'],'client_id':'integration','known_server_epoch':None}))
                        state=json.loads((await ws.receive()).data);parse_message(json.dumps(state),client=False);pid=state['payload']['worker_id']
                        await peer.setLocalDescription(await peer.createOffer());await ws.send_json(message('SDP_OFFER',{'sdp':peer.localDescription.sdp,'type':'offer'}))
                        answer=json.loads((await asyncio.wait_for(ws.receive(),30)).data);self.assertEqual(answer['type'],'SDP_ANSWER',answer)
                        await peer.setRemoteDescription(RTCSessionDescription(**answer['payload']))
                        first=await asyncio.wait_for(frames.get(),30);first_pixels=first.to_ndarray(format='rgb24')
                        await ws.send_json(message('ASSET_TRANSFORM',{'object_id':'1','mode':'preview','space':'WORLD','position':[2,0,1],'rotation_quaternion':[0,0,0,1],'scale':[1,1,1]}))
                        ack=json.loads((await ws.receive()).data);self.assertEqual(ack['type'],'ACK',ack)
                        state=json.loads((await ws.receive()).data);self.assertEqual(state['payload']['worker_id'],pid)
                        changed=False
                        for _ in range(15):
                            frame=await asyncio.wait_for(frames.get(),15)
                            if abs(frame.to_ndarray(format='rgb24').astype(float)-first_pixels).mean()>1:changed=True;break
                        self.assertTrue(changed,'Transform must change decoded WebRTC pixels')
                        meta=await asyncio.wait_for(metadata.get(),10);self.assertIsInstance(meta['rtp_timestamp'],int)
                        channel.send(json.dumps({'type':'PING','id':'proof','sent_ms':time.time()*1000}));pong=await asyncio.wait_for(pongs.get(),10);self.assertEqual(pong['id'],'proof')
                        channel.send(json.dumps({'type':'FRAME_PRESENTED','frame_id':meta['frame_id']}));frame_ack=await asyncio.wait_for(frame_acks.get(),10);self.assertGreater(frame_ack['frame_round_trip_ms'],0)
                        commit_message=message('CAMERA_UPDATE',{'camera_id':state['payload']['cameras'][0]['id'],'mode':'commit','role':'shot','matrix_order':'column-major','coordinate_space':'BLENDER_Z_UP_METERS','focal_length_mm':70})
                        await ws.send_json(commit_message);ack=json.loads((await ws.receive()).data);self.assertEqual(ack['payload']['revision'],1)
                        current=json.loads((await ws.receive()).data);parse_message(json.dumps(current),client=False);self.assertEqual(current['scene_revision'],1)
                        await ws.send_json(commit_message);duplicate=json.loads((await ws.receive()).data);self.assertEqual(duplicate['payload']['status'],'duplicate')
                        stale=message('CAMERA_UPDATE',commit_message['payload']);await ws.send_json(stale);conflict=json.loads((await ws.receive()).data);self.assertEqual(conflict['payload']['code'],'CONFLICT')
                        service.sessions[sid].bridge.process.terminate();failure=json.loads((await asyncio.wait_for(ws.receive(),10)).data);self.assertEqual(failure['payload']['code'],'WORKER_FAILED')
                        print(json.dumps({'worker_pid':pid,'decoded_size':[frame.width,frame.height],'changed_pixels':changed,'render_ms':meta['render_ms'],'rtp_timestamp':meta['rtp_timestamp']}))
            finally:
                await peer.close()
                if hasattr(self,'receiver'):self.receiver.cancel();await asyncio.gather(self.receiver,return_exceptions=True)
                await runner.cleanup()
if __name__=='__main__':unittest.main()
