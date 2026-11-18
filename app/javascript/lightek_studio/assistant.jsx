import React, {useEffect, useRef, useState} from 'react';
import {Mic, MessageCircle, X} from 'lucide-react';
import {requestKey} from './api';

const states={
  queued:'Queued Receipt',uploaded:'Queued Receipt',pending:'Queued Receipt',running:'Processing',
  processing:'Processing',draft:'Queued Receipt',publishing:'Publishing',scheduled:'Scheduled',
  delivered:'Published',needs_review:'Needs review',submitted:'Submitted · see Activity',ready:'Verified Result',completed:'Verified Result',failed:'Needs attention',
  recoverable:'Checkpoint available',awaiting_payment:'Awaiting payment',dispatched:'Processing',cancelled:'Cancelled'
};

export function Assistant({api,project,scene,tab,assetId,artifactId,activity,refresh,openResult,openCampaign,resume}) {
  const [open,setOpen]=useState(false);
  const [panel,setPanel]=useState('chat');
  const [text,setText]=useState('');
  const [messages,setMessages]=useState([]);
  const [error,setError]=useState('');
  const [busy,setBusy]=useState(false);
  const [listening,setListening]=useState(false);
  const [teaching,setTeaching]=useState(null);
  const [phrase,setPhrase]=useState('');
  const speech=useRef(null);
  const Recognition=window.SpeechRecognition || window.webkitSpeechRecognition;
  useEffect(()=>()=>speech.current?.abort(),[]);

  const pendingActions=messages.filter(message=>message.actionId&&!message.finished).map(message=>message.actionId).join(',');
  useEffect(()=>{
    if(!pendingActions)return;
    let active=true;
    async function update(){
      const ids=pendingActions.split(',').map(Number);
      const results=await Promise.allSettled(ids.map(action_id=>api.converse({action_id})));
      if(!active)return;
      const ready=new Map(results.flatMap((result,index)=>result.status==='fulfilled'?[[ids[index],result.value]]:[]));
      setMessages(previous=>previous.map(message=>{
        const row=ready.get(message.actionId);
        if(!row)return message;
        const finished=['completed','failed','cancelled','evidence_unavailable'].includes(row.status);
        const campaign=row.downstream?.result?.scene_id || row.downstream?.downstream?.result?.scene_id;
        const native=row.downstream?.type==='dispatch'||row.downstream?.downstream?.type==='dispatch';
        const marketing=['marketing_execute','feature_showcase'].some(kind=>row.kind===kind||row.downstream?.kind===kind);
        return {...message,finished,status:native&&row.status==='completed'?'submitted':row.status,campaign,marketing};
      }));
      if(ready.size)refresh();
    }
    update();
    const timer=setInterval(update,4000);
    return ()=>{active=false;clearInterval(timer);};
  },[api,pendingActions,refresh]);

  async function send(event){
    event.preventDefault();
    const instruction=text.trim();
    if(!instruction||busy)return;
    setText('');setBusy(true);setError('');
    setMessages(items=>[...items,{user:true,text:instruction}]);
    try {
      const reply=await api.converse({text:instruction,request_key:requestKey(),scene_id:scene.id,view:tab,asset_id:assetId,artifact_id:artifactId});
      setMessages(items=>[...items,{text:reply.text,status:reply.status,actionId:reply.action_id}]);
    } catch(problem){setError(problem.message);}
    finally {setBusy(false);}
  }

  function dictate(){
    if(listening){speech.current?.stop();return;}
    const recognition=new Recognition();
    speech.current=recognition;
    recognition.onstart=()=>setListening(true);
    recognition.onresult=event=>setText(value=>[value,event.results[0][0].transcript].filter(Boolean).join(' ').slice(0,2000));
    recognition.onerror=()=>setError('Voice input is unavailable. You can type your message.');
    recognition.onend=()=>setListening(false);
    try {recognition.start();} catch {setError('Voice input could not start.');}
  }

  async function teach(event){
    event.preventDefault();
    setBusy(true);setError('');
    try {
      const result=await api.converse({teach:phrase.trim(),work_item_id:teaching});
      setMessages(items=>[...items,{text:result.text}]);
      setTeaching(null);setPhrase('');setPanel('chat');
    } catch(problem){setError(problem.message);}
    finally{setBusy(false);}
  }

  return <>
    <button type="button" aria-expanded={open} onClick={()=>setOpen(!open)}><MessageCircle size={16}/> Nevaeh</button>
    {!open&&activity[0]&&<button className="ls-assistant-latest" type="button" onClick={()=>{setOpen(true);setPanel('activity');}}>{states[activity[0].status] || 'Studio activity'}</button>}
    {open&&<aside className="ls-assistant" aria-label="Nevaeh assistant">
      <div className="ls-row"><div><h2>Nevaeh</h2><small>{project.name} · {scene.name}</small></div><button aria-label="Close Nevaeh" onClick={()=>setOpen(false)}><X size={18}/></button></div>
      <div className="ls-row" aria-label="Nevaeh panels">
        <button aria-pressed={panel==='chat'} onClick={()=>setPanel('chat')}>Conversation</button>
        <button aria-pressed={panel==='activity'} onClick={()=>setPanel('activity')}>Activity</button>
      </div>
      {error&&<p role="alert" className="ls-error">{error}</p>}
      {panel==='chat'?<>
        <div className="ls-assistant-log" role="log" aria-live="polite">
          {!messages.length&&<p>Ask about this workspace or give Nevaeh a task.</p>}
          {messages.map((message,index)=><article key={index} className={message.user?'ls-assistant-user':'ls-assistant-reply'}>
            <strong>{message.user?'You':'Nevaeh'}</strong><p>{message.text}</p>
            {message.actionId&&<small>{states[message.status] || 'Needs attention'}</small>}
            {message.status==='completed'&&(message.campaign||message.marketing)&&<button onClick={()=>openCampaign(message.campaign)}>Open Publish queue</button>}
          </article>)}
        </div>
        <form onSubmit={send}><label>Message Nevaeh<textarea rows="2" value={text} onChange={event=>setText(event.target.value)} maxLength="2000" required/></label>
          <div className="ls-row">
            <button className="ls-primary" type="submit" disabled={busy || !text.trim()}>Send</button>
            {Recognition&&<button type="button" onClick={dictate} aria-pressed={listening}><Mic size={16}/> {listening?'Stop voice input':'Use voice'}</button>}
          </div>
        </form>
      </>:<div className="ls-assistant-log" aria-live="polite">
        {!activity.length&&<p>Studio tasks will appear here as they run.</p>}
        {activity.map(item=><article className="ls-card" key={item.id}>
          <div className="ls-row"><strong>{item.label}</strong><span className="ls-progress">{states[item.status] || 'Processing'}</span></div>
          {item.status==='recoverable'&&<button type="button" onClick={()=>resume(item.operation_id)}>Resume from Checkpoint</button>}
          {['ready','completed'].includes(item.status)&&<button onClick={()=>{openResult(item);setOpen(false);}}>Open result</button>}
          {item.task_uuid&&<details><summary>Receipt details</summary><small>{item.task_uuid}</small></details>}
          {item.teach&&<button type="button" onClick={()=>{setTeaching(item.id);setPhrase('');}}>Teach Nevaeh This Phrase</button>}
          {teaching===item.id&&<form onSubmit={teach}>
            <label>New phrase<input maxLength="120" value={phrase} onChange={event=>setPhrase(event.target.value)} required/></label>
            <button type="submit" disabled={busy || phrase.trim().length<3}>Save shortcut</button>
          </form>}
        </article>)}
      </div>}
    </aside>}
  </>;
}
