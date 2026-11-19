import React from 'react';
export function mechanicsAvailable(value,profile,targets){
 return !value||(['bench','carry'].includes(value.action)&&targets.some(row=>String(row.id)===value.target_id&&(row.action||'bench')===value.action&&((row.version||1)===value.version||value.action==='bench'&&value.version===1))&&(!profile||(profile.mechanics?.profile==='illustrated_biped'&&profile.mechanics.version===1&&(!(value.action==='carry'||value.version===2)||profile.views?.version===1))));
}
export function MechanicsFields({value,onChange,profile,targets=[],disabled}){
 return <fieldset disabled={disabled}><legend>Coordinated character mechanics</legend>
  <label>Coordinated action<select value={value?.target_id||''} onChange={event=>{const row=targets.find(row=>String(row.id)===event.target.value);onChange(row?{action:row.action||'bench',version:row.version||1,target_id:event.target.value}:null);}}><option value="">No coordinated action</option>{targets.map(row=><option key={row.id} value={row.id}>{row.action==='carry'?'Pick up → carry → put down':'Walk → turn → sit → speak → stand'} · {row.name}</option>)}</select></label>
  {value&&<><p className="ls-muted">Eight-second coordinated performance with planted feet and measured contacts. {value.action==='carry'?'The parcel attaches to a palm, travels with the character and releases onto its second table.':value.version===1?'This saved performance retains its original movement profile.':'The character faces the walking direction, turns, sits and speaks before standing.'} New direction-aware actions require front/side view bindings.</p>{!mechanicsAvailable(value,profile,targets)&&<p role="alert">Build a new illustrated performer or choose saved Cast with version 1 mechanics bindings, compatible character views and calibrated props.</p>}</>}
  {!targets.length&&<p className="ls-muted">Choose the bench or parcel-carry scene setup for coordinated performance.</p>}
 </fieldset>;
}
