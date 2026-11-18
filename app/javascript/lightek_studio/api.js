export function requestKey() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();

  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2,'0')).join('');
  return [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
}
export const pending = status => ['queued', 'uploaded', 'processing', 'pending', 'running', 'draft', 'publishing'].includes(status);

export function progressLabel(status) {
  if (['uploaded','pending','queued','draft'].includes(status)) return 'Queued';
  if (['processing','running','publishing'].includes(status)) return 'Processing on Worker';
  return ({ready:'Ready in Library',completed:'Completed',awaiting_payment:'Awaiting payment',
    failed:'Needs attention',cancelled:'Cancelled',recoverable:'Recoverable',expired:'Recoverable'})[status] || '';
}

export function uploadMessage(error) {
  if (error.status === 413) return 'This file is too large. Choose a smaller file and try again.';
  if (error.status === 422) return error.message;
  return 'Studio could not save this upload. Choose the file again to retry.';
}

const activityLabels={
  'workflow.create':'ComfyUI workflow draft','ai.generate':'Generation','blender.preview':'3D draft','render.quote':'3D render','performance.preview':'Character preview','timeline.quote':'Media export',
  'asset.publish':'Publishing','artifact.publish':'Publishing'
};

export function studioApi(host) {
  const activityListeners=new Set();
  const notify=receipt=>activityListeners.forEach(listener=>listener(receipt));
  const site = host?.dataset.siteId;
  const query = site ? '?site_id=' + encodeURIComponent(site) : '';
  const prefix = '/dashboard/studio-broadcasting';
  function rewrite(data) {
    if (typeof data === 'string' && /^\/api\/lightek\/pwa\/assets\/\d+\/(original|proxy|thumbnail|input)$/.test(data)) {
      return prefix + data.slice('/api/lightek/pwa'.length) + query;
    }
    if (Array.isArray(data)) return data.map(rewrite);
    if (data && typeof data === 'object') return Object.fromEntries(Object.entries(data).map(([key,value]) => [key,rewrite(value)]));
    return data;
  }
  async function call(action, payload = {}, onReceipt) {
    const capability = action === 'bootstrap' ? 'studio.pwa.bootstrap' : 'studio.workspace.' + action;
    const request = {capability, payload: action==='bootstrap'?{...payload,scope_site:true}:payload};
    if (!host) {
      const tracked=activityLabels[action] && !payload.operation_id;
      const localId=tracked?requestKey():null;
      const label=activityLabels[action];
      let receiptId;
      if(tracked)notify({id:localId,label,status:'queued',scene_id:payload.scene_id});
      try {
        const data=await window.nevaeh.execute(tracked?{...request,prefer_async:true}:request,{onReceipt:receipt=>{
          receiptId=receipt.work_item_id;
          if(tracked)notify({id:receiptId,replace:localId,label,status:'running',scene_id:payload.scene_id,task_uuid:receipt.correlation_id});
        }});
        onReceipt?.(data.correlation_id || data.work_item_id);
        if(tracked)notify({id:receiptId || localId,label,status:data.result?.status || 'processing',scene_id:payload.scene_id,
          asset_id:data.result?.asset_id,operation_id:data.result?.operation_id,task_uuid:data.correlation_id});
        return data.result;
      } catch(error){
        if(tracked)notify({id:receiptId || error.data?.work_item_id || localId,replace:localId,label,status:error.workItemId?'processing':'failed',scene_id:payload.scene_id});
        throw error;
      }
    }
    const response = await fetch(prefix + '/execute' + query, {
      method:'POST', credentials:'same-origin',
      headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':host.dataset.csrfToken},
      body:JSON.stringify(request)
    });
    const data = await window.nevaeh.parseResponse(response);
    if (data.status !== 'completed') throw Error(data.error || 'Studio could not complete this action.');
    return rewrite(data.result);
  }
  async function upload(file, projectId, key = requestKey()) {
    const body = new FormData();
    body.append('file',file);
    body.append('purpose','studio_asset');
    const response = await fetch(host ? prefix + '/uploads' + query : '/api/lightek/pwa/uploads', {
      method:'POST',credentials:'same-origin',
      headers:host ? {'X-CSRF-Token':host.dataset.csrfToken,Accept:'application/json'} : window.nevaeh.csrfHeaders(),
      body
    });
    const data = await window.nevaeh.parseResponse(response);
    return call('asset.import',{signed_id:data.signed_id,name:file.name.slice(0,160),request_key:key,project_id:projectId});
  }
  async function converse(payload) {
    return (await window.nevaeh.execute({capability:'nevaeh.conversation',payload})).result;
  }
  function onActivity(listener) {
    activityListeners.add(listener);
    return ()=>activityListeners.delete(listener);
  }
  function advanced(scene,workspace='edit') {
    const params = new URLSearchParams({advanced:'1',workspace});
    if (site) params.set('site_id',site);
    return prefix + '/workspace/' + scene + '?' + params;
  }
  return {call,upload,converse,onActivity,dashboard:!!host,site,advanced,
    native:(scene,workspace)=>host?advanced(scene,workspace):`#/studio/${scene}/${workspace}`,
    editor:(kind,scene)=>{
      if(!host || !['photo','video'].includes(kind))return null;
      return `/dashboard/studio/editors/${kind}/${scene || 'new'}${query}`;
    }};
}

export function sceneRecords(projects) {
  return (projects || []).filter(p => !p.is_template).flatMap(project => {
    const scenes = [...(project.unassigned_scenes || project.scenes || []),...(project.productions || []).flatMap(group=>group.scenes || [])];
    return [...new Map(scenes.map(scene=>[scene.id,scene])).values()].map(scene=>({project,scene}));
  });
}

export async function waitFor(get, signal, maxChecks = 120) {
  for (let index=0; index<maxChecks; index++) {
    if (signal.aborted) throw new DOMException('Cancelled','AbortError');
    const result = await get();
    if (!pending(result.status)) return result;
    await new Promise(resolve=>setTimeout(resolve,2500));
  }
  throw Error('The job is still running. Check its status before starting another.');
}
