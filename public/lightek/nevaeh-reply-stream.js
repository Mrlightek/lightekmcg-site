(() => {
  function open(key, onText) {
    let socket, timeout, active=true;
    const identifier=JSON.stringify({channel:'NevaehReplyChannel',request_key:key});
    const ready=new Promise(resolve=>{
      const finish=value=>{clearTimeout(timeout);resolve(value);};
      try {
        const url=new URL('/cable',location.href);
        url.protocol=location.protocol==='https:'?'wss:':'ws:';
        socket=new WebSocket(url,'actioncable-v1-json');
        socket.onopen=()=>socket.send(JSON.stringify({command:'subscribe',identifier}));
        socket.onmessage=event=>{
          let packet;
          try {packet=JSON.parse(event.data);} catch {return;}
          if(!active||packet.identifier!==identifier)return;
          if(packet.type==='confirm_subscription')finish(true);
          if(packet.type==='reject_subscription')finish(false);
          if(typeof packet.message?.text==='string')onText(packet.message.text);
        };
        socket.onerror=()=>finish(false);
        socket.onclose=()=>finish(false);
        timeout=setTimeout(()=>finish(false),350);
      } catch {finish(false);}
    });
    return {ready,close(){active=false;clearTimeout(timeout);socket?.close();}};
  }
  window.NevaehReplyStream = {open};
})();
