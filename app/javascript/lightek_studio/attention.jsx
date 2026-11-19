import React from 'react';
export function attentionAvailable(value,profile,targets,partner=false){
 return !value||((!profile||!!profile.bones?.head&&!!profile.attention_binding)&&Number.isFinite(value.start)&&Number.isFinite(value.end)&&value.start>=0&&value.end<=8&&value.end>value.start&&(value.kind==='camera'||value.kind==='partner'&&partner||value.kind==='object'&&targets.some(row=>String(row.id)===value.target_id)));
}
export function AttentionFields({value,onChange,targets=[],partner=false,profile,disabled,prefix='',window={start:0,end:8}}){
 const label=text=>prefix?`${prefix} ${text}`:text,selected=value?.kind==='object'?`object:${value.target_id}`:value?.kind||'';
 return <fieldset disabled={disabled}><legend>{label('attention and focal points')}</legend>
  <label>{label('attention target')}<select value={selected} onChange={event=>{const token=event.target.value;onChange(token?{kind:token.startsWith('object:')?'object':token,...(token.startsWith('object:')?{target_id:token.slice(7)}:{}),...window}:null);}}><option value="">Follow the action direction</option><option value="camera">Active camera · address the audience</option>{partner&&<option value="partner">Conversation partner</option>}{targets.map(row=><option key={row.id} value={`object:${row.id}`}>{row.name}</option>)}</select></label>
  {value&&<><div className="ls-fields">{['start','end'].map(key=><label key={key}>{label(key==='start'?'start looking':'stop looking')} (seconds)<input type="number" min="0" max="8" step="0.083333" value={value[key]} onChange={event=>onChange({...value,[key]:Number(event.target.value)})}/></label>)}</div><p className="ls-muted">Attention turns the head independently from walking direction. Head-turn limits may require a body turn to look directly at a target.</p>{!attentionAvailable(value,profile,targets,partner)&&<p role="alert">Choose a calibrated head/eye anchor, a focal point in this scene, and an attention interval within eight seconds.</p>}</>}
 </fieldset>;
}
