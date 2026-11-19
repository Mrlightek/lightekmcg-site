import React from 'react';

export function HairStyleField({label='Hairstyle',value,onChange,disabled}){
 return <label>{label}<select disabled={disabled} value={value||'curls'} onChange={event=>onChange(event.target.value)}>
  <option value="curls">Curls</option>
  <option value="close">Close cut</option>
  <option value="high_top">High top</option>
 </select></label>;
}
