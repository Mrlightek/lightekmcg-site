/* Shared workspace/dock controls for persisted, account-owned task dialogues. */
(()=>{
 const node=(tag,text)=>{const item=document.createElement(tag);if(text!==undefined)item.textContent=text;return item;};
 function render(root,result,submit){
  root.replaceChildren();const dialogue=result.task_dialogue;root.classList.toggle('nv-task-dialogue',Boolean(dialogue||result.task_choices?.length));if(!dialogue&&!result.task_choices?.length)return;
  const deliveries=new Map();
  const send=async(action,values={},text=action)=>{
   const signature=JSON.stringify([action,values,text]);if(!deliveries.has(signature))deliveries.set(signature,crypto.randomUUID());const key=deliveries.get(signature),buttons=[...root.querySelectorAll('button')];buttons.forEach(button=>button.disabled=true);
   try{await submit({dialogue_id:dialogue?.id,dialogue_action:action,dialogue_values:values,q:text,mode:'operate',request_key:key});}
   catch(error){notice.textContent=error.message;buttons.forEach(button=>button.disabled=false);}
  };
  const notice=node('p');notice.setAttribute('role','status');
  if(!dialogue){
   for(const task of result.task_choices||[]){const button=node('button',task.title);button.type='button';button.className='btn';button.onclick=()=>send('choose',{task:task.key},task.title);root.append(button);}
   root.append(notice);return;
  }
  root.classList.add('nv-task-dialogue');
  const list=node('ol');for(const step of dialogue.plan){const row=node('li');row.append(node('strong',step.title));if(Object.keys(step.inputs).length)row.append(node('p',Object.entries(step.inputs).map(([key,value])=>key.replaceAll('_',' ')+': '+value).join(' · ')));list.append(row);}root.append(list);
  if(dialogue.interpretation?.source==='local_neural')root.append(node('p','Local model suggestion. Review the task and inputs before running it.'));
  const question=dialogue.question;
  if(question){
   const form=node('form'),label=node('label',question.label);let input;
   if(Array.isArray(question.choices)){
    input=node('select');input.add(new Option('Choose…',''));for(const choice of question.choices)input.add(new Option(choice.label+' ('+choice.value+')',String(choice.value)));
   }else{input=node('input');input.type='text';input.maxLength=160;}
   input.required=true;input.setAttribute('aria-label',question.label);label.append(input);form.append(label);
   const button=node('button','Continue');button.type='submit';button.className='btn primary';button.disabled=Array.isArray(question.choices)&&!question.choices.length;form.append(button);
   form.onsubmit=event=>{event.preventDefault();send(question.field==='task'?'choose':'continue',{[question.field]:input.value},input.value);};root.append(form);
  }
  if(dialogue.status==='ready'){
   const run=node('button',dialogue.plan.length>1?'Start goal':'Run task');run.type='button';run.className='btn primary';run.onclick=()=>send('confirm');root.append(run);
  }
  if(['ready','collecting'].includes(dialogue.status)){
   const cancel=node('button','Cancel request');cancel.type='button';cancel.className='btn';cancel.onclick=()=>send('cancel');root.append(cancel);
   const note=node('p','You can also answer in chat, or say “No, I meant …” to correct the request.');root.append(note);
  }
  if(dialogue.can_teach){
   const details=node('details'),summary=node('summary','Teach this wording');details.append(summary);
   const form=node('form'),label=node('label','Wording to remember'),phrase=node('input');phrase.value=dialogue.request_text;phrase.maxLength=2000;phrase.required=true;label.append(phrase);
   form.append(label,node('p','Approve only if this is the task you meant. The successful worker report must exist before the wording can be saved.'));
   const approve=node('button','Approve this wording');approve.type='submit';approve.className='btn';form.append(approve);form.onsubmit=event=>{event.preventDefault();send('teach',{phrase:phrase.value});};details.append(form);root.append(details);
  }
  if(dialogue.learned_example_id){const forget=node('button','Forget learned wording');forget.type='button';forget.className='btn';forget.onclick=()=>send('retire_example',{example_id:dialogue.learned_example_id});root.append(forget);}
  if(dialogue.can_train){const details=node('details');details.append(node('summary','Local interpretation training'));const button=node('button','Prepare local training examples');button.type='button';button.className='btn';button.onclick=()=>send('training_dataset');details.append(node('p','Save a draft dataset from starter phrases and your reviewed examples. Use a separate internal task model in Learning & study. Training and activation remain reviewed steps.'),button);root.append(details);}
  root.append(notice);
 }
 window.NevaehTaskDialogue={render};
})();
