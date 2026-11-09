import readline from 'node:readline';
import {tiktokEvent,ssnEvent} from './normalize.mjs';
// Upstream SDK logs may include connection details. Only normalized events reach Rails.
console.log=console.warn=console.error=console.info=console.debug=()=>{};
let closed=false,connection,attempt=0,retry,watchdog,lastHeartbeat=Date.now(),sent=0,windowStart=Date.now();
function emit(data){if(closed)return;if(Date.now()-windowStart>1000){windowStart=Date.now();sent=0;}if(++sent>100)return;const line=JSON.stringify(data,(_,v)=>typeof v==='bigint'?v.toString():v);if(Buffer.byteLength(line)>8192)return;if(!process.stdout.write(line+'\n'))finish();}
function status(value){emit({type:'status',status:value});}
function finish(){if(closed)return;closed=true;clearTimeout(retry);clearInterval(watchdog);try{connection?.disconnect?.();connection?.close?.();}catch{}setTimeout(()=>process.exit(0),50).unref();}
const lines=readline.createInterface({input:process.stdin,crlfDelay:Infinity});let configured=false;
lines.on('line',async line=>{if(line.length>8192)return finish();let config;try{config=JSON.parse(line);}catch{return finish();}if(configured){if(config.type==='heartbeat')lastHeartbeat=Date.now();return;}configured=true;watchdog=setInterval(()=>{if(Date.now()-lastHeartbeat>60000)finish();},5000);
 if(config.source==='tiktok'){
  if(!/^[A-Za-z0-9_.]{1,24}$/.test(config.username||''))return finish();
  const {TikTokLiveConnection,WebcastEvent,ControlEvent}=await import('tiktok-live-connector');
  const reconnect=()=>{if(closed)return;clearTimeout(retry);if(attempt>=6){status('reconnect_exhausted');return finish();}retry=setTimeout(connect,Math.min(60000,5000*2**attempt++));};
  const connect=async()=>{if(closed)return;status('connecting');try{const next=new TikTokLiveConnection(config.username,{processInitialData:false,fetchRoomInfoOnConnect:true,authenticateWs:false,...(config.sign_api_key?{signApiKey:config.sign_api_key}:{})});connection=next;
   for(const [key,type] of [['CHAT','chat'],['MEMBER','member'],['ROOM_USER','viewers'],['GIFT','gift'],['LIKE','like'],['SOCIAL','social']])if(WebcastEvent[key])next.on(WebcastEvent[key],data=>{const event=tiktokEvent(type,data);if(event)emit(event);});
   next.on(ControlEvent.ERROR,()=>status('upstream_error'));next.on(ControlEvent.DISCONNECTED,()=>{if(closed||connection!==next)return;status('disconnected');reconnect();});
   await next.connect();if(closed){next.disconnect();return;}attempt=0;status('connected');
  }catch(error){status(error?.name==='UserOfflineError'?'offline':/sign|rate|premium/i.test(error?.name||'')?'signing_or_rate_limit':'connection_failed');try{connection?.disconnect();}catch{}reconnect();}};
  await connect();
 }else if(config.source==='ssn'){
  if(!/^[A-Za-z0-9_-]{8,128}$/.test(config.session||''))return finish();const {default:WebSocket}=await import('ws');
  const connect=()=>{if(closed)return;status('connecting');const next=new WebSocket('wss://io.socialstream.ninja',{maxPayload:65536,handshakeTimeout:15000});connection=next;next.on('open',()=>{attempt=0;next.send(JSON.stringify({join:config.session,in:4,out:5}));status('connected');});next.on('message',bytes=>{try{const event=ssnEvent(JSON.parse(bytes.toString()));if(event)emit(event);}catch{}});next.on('error',()=>status('upstream_error'));next.on('close',()=>{if(closed)return;status('disconnected');if(attempt++<6)retry=setTimeout(connect,Math.min(60000,5000*2**attempt));else finish();});};connect();
 }else finish();});
lines.on('close',finish);process.on('SIGTERM',finish);process.on('SIGINT',finish);process.on('uncaughtException',()=>{status('connection_failed');finish();});process.on('unhandledRejection',()=>{status('connection_failed');finish();});
