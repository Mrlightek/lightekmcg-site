import React from 'react';
export const contactDefaults={face:'front',hand:'right',start:1.1,reach:.5,hold:.5,release:.5};
export function contactAvailable(value,profile,targets,entrance='none'){
 if(!value)return true;
 return targets.some(row=>String(row.id)===String(value.target_id))&&(!profile||!!profile.reach_bindings?.[value.hand])&&['start','reach','hold','release'].every(key=>Number.isFinite(value[key]))&&value.start>=0&&value.start<=6&&value.reach>=.4&&value.reach<=1.5&&value.hold>=.2&&value.hold<=2&&value.release>=.4&&value.release<=1.5&&value.start+value.reach+value.hold+value.release<=8&&(entrance==='none'||value.start>=1);
}
export function ContactFields({value,onChange,targets=[],profile,disabled,prefix='',entrance='none'}){
 const label=text=>prefix?`${prefix} ${text}`:text;
 const change=(key,next)=>onChange({...value,[key]:next});
 return <fieldset disabled={disabled}><legend>{label('prop interaction')}</legend>
  <label>{label('contact prop')}<select value={value?.target_id||''} onChange={event=>onChange(event.target.value?{...contactDefaults,target_id:event.target.value}:null)}><option value="">No prop contact</option>{targets.map(row=><option key={row.id} value={row.id}>{row.name}</option>)}</select></label>
  {value&&<><div className="ls-fields"><label>{label('contact face')}<select value={value.face} onChange={event=>change('face',event.target.value)}>{['front','back','left','right','top','bottom'].map(face=><option key={face} value={face}>{face}</option>)}</select></label>
   <label>{label('contact hand')}<select value={value.hand} onChange={event=>change('hand',event.target.value)}>{['right','left'].map(hand=><option key={hand} value={hand} disabled={!!profile&&!profile.reach_bindings?.[hand]}>{hand}</option>)}</select></label></div>
   <div className="ls-fields">{[['start','reach starts',0,6],['reach','reach time',.4,1.5],['hold','hold time',.2,2],['release','release time',.4,1.5]].map(([key,text,min,max])=><label key={key}>{label(text)} (seconds)<input type="number" step="0.083333" min={min} max={max} value={value[key]} onChange={event=>change(key,Number(event.target.value))}/></label>)}</div>
   <p className="ls-muted">The renderer checks arm reach, palm contact and wrist continuity. Contact uses the selected face center of a static cube. Times snap to 12 fps; contact after an entrance must start at or after one second.</p>
   {!contactAvailable(value,profile,targets,entrance)&&<p role="alert">Choose a compatible bound hand, a prop from this setup, and contact timing within eight seconds. Older saved performers need compatible reach bindings.</p>}
  </>}
  {!targets.length&&<p className="ls-muted">Choose the Control-panel interaction setup, or a current scene containing static cube props.</p>}
 </fieldset>;
}
