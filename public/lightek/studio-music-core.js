/* Editable musical source; shared by live playback, offline bounce and MIDI interchange. */
(() => {
  const instruments=['kick','snare','hat','clap','bass','keys','pad','lead','sample'],drums=['kick','snare','hat','clap'];
  const clone=v=>JSON.parse(JSON.stringify(v)),id=()=>crypto.randomUUID();
  const track=(instrument,name=instrument)=>({id:id(),name,instrument,gain:0.75,pan:0,muted:false,solo:false,cutoff:18000,delay:0,notes:[]});
  const empty=()=>({version:1,name:'Untitled music',tempo:100,bars:4,swing:0,tracks:[track('kick','Kick'),track('snare','Snare'),track('hat','Hi-hat'),track('bass','Bass'),track('keys','Keys')]});
  function number(v,min,max,label){const n=Number(v);if(!Number.isFinite(n)||n<min||n>max)throw Error(`${label} must be between ${min} and ${max}.`);return n;}
  function validate(score){
    if(![1,2].includes(score.version))throw Error('Unsupported music project version.');
    number(score.tempo,40,240,'Tempo');number(score.bars,1,128,'Bars');if(!Number.isInteger(score.bars))throw Error('Use a whole number of bars.');
    if(seconds(score)>600)throw Error('Keep this composition within ten minutes.');number(score.swing,0,0.5,'Swing');
    if(!Array.isArray(score.tracks)||score.tracks.length<1||score.tracks.length>16)throw Error('Use 1–16 instrument tracks.');
    if(new Set(score.tracks.map(t=>t.id)).size!==score.tracks.length)throw Error('Track IDs must be unique.');let total=0;
    for(const t of score.tracks){if(!instruments.includes(t.instrument))throw Error('Unknown instrument.');number(t.gain,0,1.5,'Gain');number(t.pan,-1,1,'Pan');number(t.cutoff,100,18000,'Low-pass filter');number(t.delay,0,0.6,'Delay');const keys=new Set();
      for(const n of t.notes){if(++total>4096)throw Error('Use at most 4096 notes per song.');number(n.beat,0,score.bars*4,'Note position');number(n.length,0.015625,64,'Note length');number(n.pitch,0,127,'MIDI pitch');if(!Number.isInteger(n.pitch))throw Error('MIDI notes must be whole numbers.');number(n.velocity,0.01,1,'Velocity');if(n.beat>=score.bars*4||n.beat+n.length>score.bars*4+0.000001)throw Error('A note extends beyond the song.');const key=n.beat+':'+(drums.includes(t.instrument)?'drum':n.pitch);if(keys.has(key))throw Error('Remove duplicate notes at the same beat and pitch.');keys.add(key);}
      if(t.instrument==='sample'){if(!Number.isInteger(t.asset_id)||t.asset_id<=0)throw Error('Choose a prepared audio sample.');number(t.sample_in,0,600,'Sample in');number(t.sample_out,t.sample_in+0.01,t.sample_in+30,'Sample out');number(t.root,0,127,'Sample root');}
    }validatePatterns(score);return score;
  }
  function validatePatterns(score){
    const patterns=score.patterns||[],playlist=score.playlist||[];
    if(score.version===1&&(patterns.length||playlist.length))throw Error('Reusable patterns require music source version 2.');
    if(!Array.isArray(patterns)||patterns.length>32||!Array.isArray(playlist)||playlist.length>128)throw Error('Use at most 32 patterns and 128 placements.');
    const goodId=value=>typeof value==='string'&&/^[a-zA-Z0-9_-]{1,60}$/.test(value);
    let total=score.tracks.reduce((sum,t)=>sum+t.notes.length,0);
    const ids=new Set();
    for(const p of patterns){
      if(!goodId(p.id)||ids.has(p.id))throw Error('Pattern IDs must be unique.');ids.add(p.id);
      number(p.bars,1,16,'Pattern bars');if(!Number.isInteger(p.bars))throw Error('Pattern bars must be whole numbers.');
      if(!Array.isArray(p.tracks)||p.tracks.length>16||new Set(p.tracks.map(t=>t.track_id)).size!==p.tracks.length)throw Error('Pattern channels must be unique.');
      const tracks=p.tracks.map(lane=>{const channel=score.tracks.find(t=>t.id===lane.track_id);if(!channel)throw Error('A pattern references a missing instrument channel.');if(!Array.isArray(lane.notes))throw Error('Pattern notes must be a list.');total+=lane.notes.length;return{...channel,notes:lane.notes};});
      if(total>4096)throw Error('Use at most 4096 source notes across song and patterns.');
      if(tracks.length)validate({version:1,tempo:score.tempo,bars:p.bars,swing:0,tracks});
    }
    const placements=new Set();
    for(const clip of playlist){
      const p=patterns.find(p=>p.id===clip.pattern_id);
      if(!p||!goodId(clip.id)||placements.has(clip.id))throw Error('Placements need unique IDs and an existing pattern.');placements.add(clip.id);
      number(clip.bar,0,score.bars-1,'Placement bar');number(clip.repeat,1,32,'Pattern repeats');number(clip.transpose,-24,24,'Transpose');number(clip.velocity,0,1,'Placement strength');
      if(![clip.bar,clip.repeat,clip.transpose].every(Number.isInteger)||clip.bar+p.bars*clip.repeat>score.bars)throw Error('The pattern placement extends beyond the song or uses fractional bars/repeats.');
    }
    expanded(score);
  }
  function expanded(score){
    const tracks=score.tracks.map(t=>({...t,notes:t.notes.map(n=>({...n}))}));let count=tracks.reduce((sum,t)=>sum+t.notes.length,0);
    for(const clip of score.playlist||[]){const p=score.patterns.find(p=>p.id===clip.pattern_id);
      for(let repeat=0;repeat<clip.repeat;repeat++)for(const lane of p.tracks){const t=tracks.find(t=>t.id===lane.track_id);
        for(const n of lane.notes){if(++count>16384)throw Error('The expanded playlist exceeds 16384 notes.');const pitch=n.pitch+(drums.includes(t.instrument)?0:clip.transpose);if(pitch<0||pitch>127)throw Error('A transposed pattern note is outside MIDI range.');
          if(!clip.muted&&clip.velocity>0)t.notes.push({...n,beat:clip.bar*4+repeat*p.bars*4+n.beat,pitch,velocity:n.velocity*clip.velocity});
        }
      }
    }
    for(const t of tracks){const seen=new Set();for(const n of t.notes){const key=n.beat.toFixed(6)+':'+(drums.includes(t.instrument)?'drum':n.pitch);if(seen.has(key))throw Error('Pattern placements overlap notes on the same channel and pitch. Move the placement or clear those song notes.');seen.add(key);}t.notes.sort((a,b)=>a.beat-b.beat||a.pitch-b.pitch);}
    return tracks;
  }
  function makePattern(score,bar=null){
    score.version=2;score.patterns ||= [];score.playlist ||= [];
    const p={id:id(),name:'Pattern '+(score.patterns.length+1),bars:1,tracks:score.tracks.map(t=>({track_id:t.id,notes:bar===null?[]:t.notes.filter(n=>n.beat>=bar*4&&n.beat<(bar+1)*4).map(n=>({...n,beat:n.beat-bar*4,length:Math.min(n.length,(bar+1)*4-n.beat)}))}))};
    score.patterns.push(p);validate(score);return p;
  }
  function editor(score,patternId){
    const p=score.patterns?.find(p=>p.id===patternId);if(!p)return score;
    const tracks=score.tracks.map(t=>{
      let lane=p.tracks.find(l=>l.track_id===t.id);if(!lane){lane={track_id:t.id,notes:[]};p.tracks.push(lane);}
      return new Proxy(t,{get:(target,name)=>name==='notes'?lane.notes:target[name],set:(target,name,value)=>{if(name==='notes')lane.notes=value;else target[name]=value;return true;}});
    });
    return {...score,bars:p.bars,tracks,patterns:[],playlist:[]};
  }
  const seconds=s=>s.bars*4*60/s.tempo;
  function events(score,onlyTrack=null){validate(score);const solo=score.tracks.some(t=>t.solo);return expanded(score).flatMap(t=>(onlyTrack?t.id===onlyTrack:!t.muted&&(!solo||t.solo))?t.notes.map(n=>{const sixteenth=n.beat*4,shift=Math.abs(sixteenth-Math.round(sixteenth))<0.00001&&Math.round(sixteenth)%2?score.swing/4:0;return{track:t.id,instrument:t.instrument,pitch:n.pitch,velocity:n.velocity,time:(n.beat+shift)*60/score.tempo,duration:n.length*60/score.tempo};}):[]).sort((a,b)=>a.time-b.time);}
  function toggle(score,trackId,bar,step,pitch,length=0.25,velocity=0.8){const t=score.tracks.find(t=>t.id===trackId);if(!t)throw Error('Choose a track.');const beat=bar*4+step/4,index=t.notes.findIndex(n=>Math.abs(n.beat-beat)<0.00001&&(drums.includes(t.instrument)||n.pitch===pitch));if(index>=0)t.notes.splice(index,1);else t.notes.push({beat,pitch,length:Math.min(length,score.bars*4-beat),velocity});validate(score);}
  function copyBar(score,bar,repeat=false){if(bar>=score.bars-1)throw Error('Add another bar before copying this one.');const next=clone(score);for(const t of next.tracks){const notes=t.notes.filter(n=>n.beat>=bar*4&&n.beat<(bar+1)*4);for(let dest=bar+1;dest<(repeat?score.bars:bar+2);dest++){t.notes=t.notes.filter(n=>n.beat<dest*4||n.beat>=(dest+1)*4);t.notes.push(...notes.map(n=>({...n,beat:n.beat-bar*4+dest*4,length:Math.min(n.length,(score.bars-dest)*4-(n.beat-bar*4))})));}}return validate(next);}
  function toMidi(score){validate(score);const midi=new window.Midi();midi.name=score.name;midi.header.setTempo(score.tempo);midi.header.timeSignatures.push({ticks:0,timeSignature:[4,4]});let channel=0;for(const t of expanded(score)){const dest=midi.addTrack();dest.name=t.name;if(drums.includes(t.instrument))dest.channel=9;else{if(channel===9)channel++;if(channel>15)throw Error('MIDI supports fifteen melodic channels plus a drum channel. Export some tracks as audio stems.');dest.channel=channel++;};dest.instrument.number={bass:32,keys:0,pad:88,lead:80}[t.instrument]||0;for(const n of t.notes)dest.addNote({midi:drums.includes(t.instrument)?{kick:36,snare:38,hat:42,clap:39}[t.instrument]:n.pitch,ticks:Math.round(n.beat*midi.header.ppq),durationTicks:Math.max(1,Math.round(n.length*midi.header.ppq)),velocity:n.velocity});}return midi.toArray();}
  function fromMidi(bytes,name){const midi=new window.Midi(bytes),tempos=midi.header.tempos;if(tempos.some(t=>Math.abs(t.bpm-(tempos[0]?.bpm||120))>0.001)||midi.header.timeSignatures.some(t=>t.timeSignature[0]!==4||t.timeSignature[1]!==4))throw Error('This music editor currently imports a constant tempo and 4/4 meter.');const score={version:1,name:name||midi.name||'Imported MIDI',tempo:tempos[0]?.bpm||120,bars:1,swing:0,tracks:[]};for(const source of midi.tracks){if(!source.notes.length)continue;const groups=new Map();for(const n of source.notes){const instrument=source.channel===9?([35,36].includes(n.midi)?'kick':[38,40].includes(n.midi)?'snare':[42,44,46].includes(n.midi)?'hat':n.midi===39?'clap':null):source.instrument.family==='bass'?'bass':source.instrument.family==='synth pad'?'pad':'keys';if(!instrument)throw Error('This MIDI drum kit includes sounds that need custom sample mapping.');if(!groups.has(instrument))groups.set(instrument,track(instrument,source.name||instrument));const dest=groups.get(instrument),note={beat:n.ticks/midi.header.ppq,length:n.durationTicks/midi.header.ppq,pitch:drums.includes(instrument)?60:n.midi,velocity:n.velocity};if(dest.notes.some(a=>a.beat===note.beat&&a.pitch===note.pitch))continue;dest.notes.push(note);score.bars=Math.max(score.bars,Math.ceil((note.beat+note.length)/4));}score.tracks.push(...groups.values());}return validate(score);}
  function wav(buffer){const channels=Math.min(2,buffer.numberOfChannels),length=buffer.length,rate=buffer.sampleRate,bytes=new ArrayBuffer(44+length*channels*2),view=new DataView(bytes);const text=(at,s)=>{for(let i=0;i<s.length;i++)view.setUint8(at+i,s.charCodeAt(i));};text(0,'RIFF');view.setUint32(4,36+length*channels*2,true);text(8,'WAVE');text(12,'fmt ');view.setUint32(16,16,true);view.setUint16(20,1,true);view.setUint16(22,channels,true);view.setUint32(24,rate,true);view.setUint32(28,rate*channels*2,true);view.setUint16(32,channels*2,true);view.setUint16(34,16,true);text(36,'data');view.setUint32(40,length*channels*2,true);const planes=Array.from({length:channels},(_,i)=>buffer.getChannelData(i));for(let i=0;i<length;i++)for(let c=0;c<channels;c++){const sample=Math.max(-1,Math.min(1,Number.isFinite(planes[c][i])?planes[c][i]:0));view.setInt16(44+(i*channels+c)*2,sample<0?sample*32768:sample*32767,true);}return bytes;}
  window.LightekMusicCore={instruments,drums,track,empty,clone,validate,validatePatterns,expanded,makePattern,editor,seconds,events,toggle,copyBar,toMidi,fromMidi,wav};
})();
