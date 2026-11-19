import React from 'react';
export const actingDefaults={emotion:'neutral',body_action:'still',entrance:'none'};
export function actingAvailable(values,profile){
 if(!profile)return true;
 const face={friendly:'smile',curious:'brow_raise',surprised:'brow_raise'}[values.emotion];
 const action={point_left:'Point left',point_right:'Point right'}[values.body_action];
 return (!face||!!profile.bindings?.[face])&&(!action||profile.motions?.some(row=>row.name===action))&&(values.entrance==='none'||profile.motions?.some(row=>row.name==='Step in place'));
}
export function ActingFields({value,onChange,disabled,profile,prefix='',contactActive=false}){
 const values={...actingDefaults,...value};
 const label=text=>prefix?`${prefix} ${text}`:text;
 return <><div className="ls-fields">
  <label>{label('facial cue')}<select disabled={disabled} value={values.emotion} onChange={event=>onChange('emotion',event.target.value)}>{[['neutral','Neutral'],['friendly','Friendly smile'],['curious','Curious brows'],['surprised','Surprised brows']].map(([key,text])=><option key={key} value={key} disabled={!actingAvailable({...actingDefaults,emotion:key},profile)}>{text}</option>)}</select></label>
  <label>{label('body action')}<select disabled={disabled||contactActive} value={values.body_action} onChange={event=>onChange('body_action',event.target.value)}>{[['still','No added body action'],['point_left','Point left'],['point_right','Point right']].map(([key,text])=><option key={key} value={key} disabled={!actingAvailable({...actingDefaults,body_action:key},profile)}>{text}</option>)}</select></label>
  <label>{label('entrance')}<select disabled={disabled} value={values.entrance} onChange={event=>onChange('entrance',event.target.value)}>{[['none','Already on stage'],['from_left','Step in from left'],['from_right','Step in from right']].map(([key,text])=><option key={key} value={key} disabled={!actingAvailable({...actingDefaults,entrance:key},profile)}>{text}</option>)}</select></label>
 </div><p className="ls-muted">New illustrated performers include pointing and a short step-in entrance. Saved performers expose only their own registered motions. Pointing is a pose; it does not automatically touch a prop.</p>{!actingAvailable(values,profile)&&<p role="alert">Choose an action supported by this saved performer, or build a new illustrated performer.</p>}</>;
}
