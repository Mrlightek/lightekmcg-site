import React from 'react';
export function mechanicsAvailable(value,profile,targets){
 return !value||(value.action==='bench'&&value.version===1&&targets.some(row=>String(row.id)===value.target_id)&&(!profile||(profile.mechanics?.profile==='illustrated_biped'&&profile.mechanics.version===1)));
}
export function MechanicsFields({value,onChange,profile,targets=[],disabled}){
 return <fieldset disabled={disabled}><legend>Coordinated character mechanics</legend>
  <label>Coordinated action<select value={value?.target_id||''} onChange={event=>onChange(event.target.value?{action:'bench',version:1,target_id:event.target.value}:null)}><option value="">No coordinated action</option>{targets.map(row=><option key={row.id} value={row.id}>Walk → turn → sit → speak → stand · {row.name}</option>)}</select></label>
  {value&&<><p className="ls-muted">Eight-second bench performance with planted-foot solving and measured seat support. Uses calibrated illustrated biped mechanics v1; dialogue starts while seated. Movement and prop contact are coordinated by this action.</p>{!mechanicsAvailable(value,profile,targets)&&<p role="alert">Build a new illustrated performer or choose saved Cast with version 1 mechanics bindings and the calibrated bench seat.</p>}</>}
  {!targets.length&&<p className="ls-muted">Choose the Walk, sit and stand scene setup for the first coordinated performance.</p>}
 </fieldset>;
}
