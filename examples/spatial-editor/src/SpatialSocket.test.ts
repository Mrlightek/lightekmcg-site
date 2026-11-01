import {test} from 'node:test';import assert from 'node:assert/strict';import {SpatialSocket} from './SpatialSocket.js';
class FakeSocket {
 static OPEN=1;static instances:FakeSocket[]=[];readyState=1;bufferedAmount=0;sent:any[]=[];onopen:(()=>void)|null=null;onmessage:((event:any)=>void)|null=null;onclose:(()=>void)|null=null;onerror:(()=>void)|null=null;
 constructor(_url:string){FakeSocket.instances.push(this);}
 send(value:string){this.sent.push(JSON.parse(value));}close(){this.readyState=3;}
 receive(type:string,payload:any,revision=0){this.onmessage?.({data:JSON.stringify({v:1,type,session_id:'session',scene_revision:revision,payload})});}
}
(globalThis as any).WebSocket=FakeSocket;
const credentials=async()=>({session_id:'session',ticket:'ticket',ws_url:'wss://test',ice_servers:[],backend:'render',encoder:'libx264'});
test('previews coalesce; durable messages wait for receipts and retain their original revision across reconnect',async()=>{
 const manager=new SpatialSocket({credentials,onStatus:()=>{},onRecovery:()=>assert.fail('Unexpected recovery'),onMessage:()=>{}});
 await manager.connect();const socket=FakeSocket.instances.at(-1)!;
 manager.send('TIMELINE_SCRUB',{frame:1},'timeline');manager.send('TIMELINE_SCRUB',{frame:2},'timeline');assert.equal(socket.sent.length,0);
 socket.onopen?.();socket.receive('SERVER_STATE',{server_epoch:'epoch',recent_receipts:[]},3);
 assert.equal(socket.sent.find(m=>m.type==='TIMELINE_SCRUB').payload.frame,2);
 const id=manager.send('ASSET_TRANSFORM',{mode:'commit',object_id:'one'});const first=socket.sent.find(m=>m.message_id===id);assert.equal(first.scene_revision,3);
 await manager.connect();const reconnect=FakeSocket.instances.at(-1)!;reconnect.onopen?.();reconnect.receive('SERVER_STATE',{server_epoch:'epoch',recent_receipts:[]},4);
 assert.deepEqual(reconnect.sent.find(m=>m.message_id===id),first);
 reconnect.receive('ACK',{command_id:id},4);manager.close();
});
test('worker epoch change blocks uncertain durable replay',async()=>{
 let recoveries=0;const manager=new SpatialSocket({credentials,onStatus:()=>{},onRecovery:()=>recoveries++,onMessage:()=>{}});
 await manager.connect();const socket=FakeSocket.instances.at(-1)!;socket.onopen?.();socket.receive('SERVER_STATE',{server_epoch:'one',recent_receipts:[]});manager.send('ASSET_TRANSFORM',{mode:'commit'});
 socket.receive('SERVER_STATE',{server_epoch:'two',recent_receipts:[]});assert.equal(recoveries,1);assert.equal(manager.pendingEdits().length,1);manager.close();
});
