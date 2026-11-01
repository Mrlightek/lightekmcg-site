import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createEditorStore} from './store.js';
import {TimelineSync,type PreviewDemand,type DecodedFrame} from './TimelineSync.js';
import {evaluateFrame,frameToMicroseconds,transformAt,type Project,type Transform} from './timeline.js';
const transform=(x:number):Transform=>({position:[x,0,0],rotation:[0,0,0,1],scale:[1,1,1]});
const project:Project={sceneId:4,revision:7,blenderFrameStart:1,fps:{num:30000,den:1001},durationFrames:300,defaultCameraId:'a',tracks:[
 {id:'motion',kind:'transform',name:'Character movement',objectId:'iris',keyframes:[{frame:0,value:transform(0),interpolation:'linear'},{frame:100,value:transform(10),interpolation:'linear'}]},
 {id:'cuts',kind:'camera',name:'Director',cuts:[{frame:80,cameraId:'b'}]},
 {id:'sound',kind:'audio',name:'Dialogue',enabled:true,muted:false,clips:[{id:'clip1',assetId:'asset1',startFrame:20,durationFrames:100,sourceInFrame:30,sourceFps:{num:30,den:1},gain:1}]}
]};
function fixture(){
 const store=createEditorStore(project),sent:PreviewDemand[]=[],evaluated:number[]=[],pending:boolean[]=[];
 const sync=new TimelineSync(store,{evaluate:frame=>{evaluated.push(frame.frame);},setPending:value=>{pending.push(value);},alignToPresentedCamera:()=>{}},{send:message=>{sent.push(message);}},'session',10000);
 let presented=0,discarded=0;
 const decoded=(request:PreviewDemand,overrides={}):DecodedFrame=>({metadata:{sessionId:'session',sceneRevision:request.sceneRevision,requestSeq:request.seq,frame:request.frame,blenderFrame:request.blenderFrame,cameraId:request.cameraId,frameId:'frame',viewMatrix:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],projectionMatrix:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],...overrides},present:()=>{presented++;},discard:()=>{discarded++;}});
 return {store,sent,evaluated,pending,sync,decoded,counts:()=>({presented,discarded})};
}
test('rational frame times, clip offsets, camera cuts and interpolated transforms',()=>{
 assert.equal(frameToMicroseconds(30000,project.fps),1001000000n);
 assert.throws(()=>frameToMicroseconds(1,{num:0,den:1}));
 const frame=evaluateFrame(project,50);assert.equal(frame.transforms.get('iris')!.position[0],5);assert.equal(frame.cameraId,'a');
 assert.equal(evaluateFrame(project,80).cameraId,'b');assert.equal(evaluateFrame(project,120).media.length,0);
 assert(Math.abs(frame.media[0].sourceSeconds-2.001)<.00001);
 assert.equal(transformAt([],5),undefined);
});
test('scrubbing updates local proxies immediately and coalesces backend work',()=>{
 const f=fixture();f.sync.seek(10);f.sync.seek(20);f.sync.seek(95);assert.deepEqual(f.evaluated,[10,20,95]);assert.equal(f.sent.length,0);
 f.sync.flush();assert.equal(f.sent.length,1);assert.equal(f.sent[0].frame,95);assert.equal(f.sent[0].cameraId,'b');assert.equal(f.store.getState().displayedFrame,null);
 f.sync.dispose();
});
test('a release commits the exact last frame without waiting for debounce',()=>{
 const f=fixture();f.sync.seek(10);f.sync.seek(85,true);assert.equal(f.sent.length,1);assert.equal(f.sent[0].frame,85);f.sync.dispose();
});
test('outdated session, revision, sequence, camera and frame never replace visible pixels',()=>{
 const f=fixture();f.sync.seek(90,true);const request=f.sent[0];
 for(const wrong of [{sessionId:'old'},{sceneRevision:6},{requestSeq:0},{cameraId:'a'},{frame:89},{blenderFrame:90}])assert.equal(f.sync.acceptDecodedFrame(f.decoded(request,wrong)),false);
 assert.equal(f.counts().presented,0);assert.equal(f.counts().discarded,6);assert.equal(f.store.getState().pending,true);
 assert(f.sync.acceptDecodedFrame(f.decoded(request)));assert.equal(f.store.getState().displayedFrame,90);assert.equal(f.store.getState().pending,false);assert.equal(f.counts().presented,1);
 f.sync.dispose();
});
test('a newer scrub invalidates a frame even while an older render is in flight',()=>{
 const f=fixture();f.sync.seek(10,true);const old=f.sent[0];f.sync.seek(40);
 assert.equal(f.sync.acceptDecodedFrame(f.decoded(old)),false);assert.equal(f.store.getState().displayedFrame,null);f.sync.flush();
 assert(f.sync.acceptDecodedFrame(f.decoded(f.sent[1])));assert.equal(f.store.getState().displayedFrame,40);f.sync.dispose();
});
test('paint failure retains pending state; project revisions invalidate prior decoded frames',()=>{
 const f=fixture();f.sync.seek(10,true);const old=f.sent[0],broken=f.decoded(old);broken.present=()=>{throw new Error('Decoder surface lost');};
 assert.equal(f.sync.acceptDecodedFrame(broken),false);assert.equal(f.store.getState().displayedFrame,null);assert.match(f.store.getState().lastError!,/surface lost/);
 f.sync.replaceProject({...project,revision:8});assert.equal(f.sent.at(-1)!.sceneRevision,8);assert.equal(f.sync.acceptDecodedFrame(f.decoded(old)),false);
 f.sync.dispose();assert.equal(f.sync.acceptDecodedFrame(f.decoded(f.sent.at(-1)!)),false);assert.throws(()=>f.sync.seek(20));
});

test('wire adapter sends revisioned preview demands and rejects disconnected channels',async()=>{
 const {WebSocketPreviewTransport}=await import('./WebSocketPreviewTransport.js');
 const messages:string[]=[],socket={readyState:1,bufferedAmount:0,send:(data:string)=>{messages.push(data);}};
 const transport=new WebSocketPreviewTransport(socket);
 const request:PreviewDemand={v:1,type:'preview.demand',sessionId:'s',sceneId:4,sceneRevision:7,seq:3,frame:100,blenderFrame:101,cameraId:'b'};
 transport.send(request);assert.deepEqual(JSON.parse(messages[0]),{v:1,type:'preview.demand',session_id:'s',scene_id:4,scene_revision:7,request_seq:3,frame:100,blender_frame:101,camera_ids:['b']});
 socket.readyState=3;assert.throws(()=>transport.send(request),/disconnected/);socket.readyState=1;socket.bufferedAmount=100000;assert.throws(()=>transport.send(request),/congested/);
});
test('Three adapter applies evaluated transforms and animation time before preview acknowledgement',async()=>{
 const {ThreeTimelineAdapter}=await import('./ThreeTimelineAdapter.js');let x=0,time=0,camera='',worldUpdated=false;
 const adapter=new ThreeTimelineAdapter({objects:new Map([['iris',{position:{set:(value:number)=>{x=value;}},quaternion:{set:()=>{}},scale:{set:()=>{}},updateMatrixWorld:()=>{worldUpdated=true;}}]]),mixers:[{setTime:value=>{time=value;}}],selectShotCamera:id=>{camera=id;},seekMedia:()=>{},setGhostPicking:()=>{},applyPresentedMatrices:()=>{}});
 adapter.evaluate(evaluateFrame(project,90));assert.equal(x,9);assert(Math.abs(time-3.003)<1e-6);assert.equal(camera,'b');assert(worldUpdated);
});
