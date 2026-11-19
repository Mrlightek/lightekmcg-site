import React from 'react';

export function PortraitField({label='Portrait mask',assets,value='',onChange,disabled}){
 const photos=assets.filter(asset=>asset.kind==='image'&&asset.status==='ready');
 return <label>{label}<select disabled={disabled} value={value} onChange={event=>onChange(event.target.value)}>
  <option value="">Use the illustrated face</option>
  {value&&!photos.some(asset=>String(asset.id)===value)&&<option value={value}>Previously selected portrait</option>}
  {photos.map(asset=><option key={asset.id} value={asset.id}>{asset.name}</option>)}
 </select></label>;
}

export function HairStyleField({label='Hairstyle',value,onChange,disabled}){
 return <label>{label}<select disabled={disabled} value={value||'curls'} onChange={event=>onChange(event.target.value)}>
  <option value="curls">Curls</option>
  <option value="close">Close cut</option>
  <option value="high_top">High top</option>
 </select></label>;
}
