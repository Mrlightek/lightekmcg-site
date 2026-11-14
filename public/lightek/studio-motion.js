/* Source-bound native Actions, arranged independently of dialogue takes. */
(() => {
  const drafts=new Map();let selected=null,busy=false;
  const escape=value=>E(String(value??''));
  const key=(scene,object)=>`${scene.id}:${object.id}`;
  function state(scene,object){
    const id=key(scene,object),revision=object.definition.motion_revision||0;
    if(!drafts.has(id)||(!drafts.get(id).dirty&&drafts.get(id).revision!==revision))drafts.set(id,{clips:structuredClone(object.definition.motion_clips||[]),revision,dirty:false,error:'',request:null});
    return drafts.get(id);
  }
  function capture(){
    const form=app.querySelector('[data-motion-form]');if(!form||!selected)return;
    const data=new FormData(form),entry=drafts.get(selected);
    entry.clips=entry.clips.map((clip,i)=>({...clip,...Object.fromEntries(['action_id','mode'].map(name=>[name,data.get(`${i}_${name}`)])),...Object.fromEntries(['source_in','source_out','start','speed','repeat','strength','layer','blend_in','blend_out'].map(name=>[name,Number(data.get(`${i}_${name}`))]))}));
  }
  function view(record,object){
    if(!object)return '';const next=key(record.scene,object);if(selected!==next){capture();selected=next;}
    const entry=state(record.scene,object),actions=object.definition.character_profile?.motions||[];
    const options=(list,value)=>list.map(([id,label])=>`<option value="${escape(id)}" ${String(value)===String(id)?'selected':''}>${escape(label)}</option>`).join('');
    const field=(i,name,label,value,step='any')=>`<label class="fld"><span>${escape(label)}</span><input name="${i}_${name}" type="number" required step="${step}" value="${escape(value)}"></label>`;
    return `<section class="studio-motion"><header><h3>Body motion clips</h3><p>Arrange the native motions stored with this character. Save motions before previewing or exporting.</p></header>${!actions.length?'<p>No source actions are registered. Reimport a character with an active or stashed NLA action and register its updated Cast source. New starter performers include head and arm motions.</p>':''}
      ${entry.error?`<p role="alert">${escape(entry.error)}</p>`:''}<form data-motion-form><fieldset ${busy?'disabled':''}><div class="studio-motion-clips">${entry.clips.map((clip,i)=>{
        const action=actions.find(a=>a.id===clip.action_id),duration=action?(clip.source_out-clip.source_in)/action.fps/clip.speed*clip.repeat:0;
        return `<article><div class="pwa-post-actions"><strong>Clip ${i+1}</strong><button type="button" class="btn sm" data-motion="duplicate" data-index="${i}" ${busy?'disabled':''}>Duplicate</button><button type="button" class="btn sm" data-motion="remove" data-index="${i}" ${busy?'disabled':''}>Remove</button></div>
          <label class="fld"><span>Source motion</span><select name="${i}_action_id" data-motion-action="${i}">${options(actions.map(a=>[a.id,`${a.name} · ${a.rig}`]),clip.action_id)}</select></label>
          <p>Source ${action?.frame_start??'—'}–${action?.frame_end??'—'} frames at ${action?.fps??'—'} fps · clip length ${Number.isFinite(duration)?duration.toFixed(2):'—'} seconds</p><div class="studio-motion-fields">
          ${field(i,'source_in','Source in · frame',clip.source_in)}${field(i,'source_out','Source out · frame',clip.source_out)}${field(i,'start','Scene start · seconds',clip.start)}${field(i,'speed','Playback speed · 0.25–4',clip.speed)}${field(i,'repeat','Repeats · 1–20',clip.repeat,1)}${field(i,'strength','Strength · 0–1',clip.strength)}${field(i,'layer','Layer · 0–3',clip.layer,1)}${field(i,'blend_in','Blend in · seconds',clip.blend_in)}${field(i,'blend_out','Blend out · seconds',clip.blend_out)}
          <label class="fld"><span>Layer blend</span><select name="${i}_mode">${options([['REPLACE','Replace'],['ADD','Additive']],clip.mode)}</select></label></div></article>`;
      }).join('')}</div><div class="pwa-post-actions"><button type="button" class="btn" data-motion="add" ${busy||!actions.length||entry.clips.length>=32?'disabled':''}>Add motion clip</button><button class="btn p" ${busy?'disabled':''}>${busy?'Saving…':'Save motion arrangement'}</button><button type="button" class="btn sm" data-motion="reload" ${busy?'disabled':''}>Reload saved motions</button></div><p role="status">${entry.dirty?'Unsaved motion changes':'Motion arrangement saved'} · ${entry.clips.length} clips</p><p>Layers play from 0 to 3 using Blender’s influence blending. Clips on one layer may overlap only inside both blend ramps. Additive actions should contain motion offsets. Clearing the arrangement restores the character’s original source animation.</p></fieldset></form></section>`;
  }
  function current(){const record=studioSceneRecord(studioCurrentSceneId()),object=record?.scene.objects.find(o=>key(record.scene,o)===selected);return{record,object};}
  function repaint(){LightekStudioPerformance.capture();render(1);}
  app.addEventListener('input',event=>{if(event.target.closest('[data-motion-form]')&&selected){capture();drafts.get(selected).dirty=true;}});
  app.addEventListener('change',event=>{
    if(!event.target.hasAttribute('data-motion-action'))return;capture();const {object}=current(),entry=drafts.get(selected),clip=entry.clips[Number(event.target.dataset.motionAction)],action=object.definition.character_profile.motions.find(a=>a.id===clip.action_id);
    clip.source_in=action.frame_start;clip.source_out=action.frame_end;entry.dirty=true;repaint();
  });
  app.addEventListener('click',async event=>{
    const button=event.target.closest('[data-motion]');if(!button||busy||LightekStudioPerformance.busy())return;capture();const {record,object}=current();if(!object)return;
    const entry=state(record.scene,object),actions=object.definition.character_profile.motions||[],index=Number(button.dataset.index);
    if(button.dataset.motion==='reload'){
      const id=selected;busy=true;repaint();
      try{LightekStudioPerformance.capture();await A.studioLoad(true);if(selected===id){const updated=current().object;if(updated){entry.clips=structuredClone(updated.definition.motion_clips||[]);entry.revision=updated.definition.motion_revision||0;entry.dirty=false;entry.error='';entry.request=null;}}}
      catch(error){entry.error=error.message;}finally{busy=false;repaint();}return;
    }
    if(button.dataset.motion==='add'&&actions.length&&entry.clips.length<32){const action=actions[0];entry.clips.push({id:crypto.randomUUID(),action_id:action.id,source_in:action.frame_start,source_out:action.frame_end,start:0,speed:1,repeat:1,strength:1,layer:0,blend_in:0,blend_out:0,mode:'REPLACE'});}
    if(button.dataset.motion==='duplicate'&&entry.clips.length<32){const old=entry.clips[index],action=actions.find(a=>a.id===old.action_id);entry.clips.splice(index+1,0,{...old,id:crypto.randomUUID(),start:old.start+(old.source_out-old.source_in)/action.fps/old.speed*old.repeat});}
    if(button.dataset.motion==='remove')entry.clips.splice(index,1);
    entry.dirty=true;repaint();
  });
  app.addEventListener('submit',async event=>{
    if(!event.target.matches('[data-motion-form]'))return;event.preventDefault();if(busy||LightekStudioPerformance.busy())return;capture();LightekStudioPerformance.capture();
    const {record,object}=current();if(!object)return;const entry=state(record.scene,object),signature=JSON.stringify([entry.clips,entry.revision]);
    if(entry.request?.signature!==signature)entry.request={signature,key:crypto.randomUUID()};busy=true;entry.error='';repaint();
    try{await nevaeh.execute({capability:'studio.workspace.motion.save',payload:{scene_id:record.scene.id,object_id:object.id,lock_version:record.scene.lock_version,motion_revision:entry.revision,clips:entry.clips,request_key:entry.request.key}});entry.dirty=false;entry.request=null;LightekStudioPerformance.capture();await A.studioLoad(true);toast('Motion arrangement saved. Preview the performance to review it.');}
    catch(error){entry.error=error.message;}
    finally{busy=false;repaint();}
  });
  window.LightekStudioMotion={view,capture,busy:()=>busy,dirty:(sceneId=studioCurrentSceneId())=>[...drafts].some(([id,entry])=>id.startsWith(sceneId+':')&&entry.dirty),hasDrafts:()=>[...drafts.values()].some(entry=>entry.dirty)};
})();
