export const requestKey = () => crypto.randomUUID();
export const pending = status => ['queued', 'uploaded', 'processing', 'pending', 'running', 'draft', 'publishing'].includes(status);

export function studioApi(host) {
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
  async function call(action, payload = {}) {
    const capability = action === 'bootstrap' ? 'studio.pwa.bootstrap' : 'studio.workspace.' + action;
    const request = {capability, payload: action==='bootstrap'?{...payload,scope_site:true}:payload};
    if (!host) return (await window.nevaeh.execute(request)).result;
    const response = await fetch(prefix + '/execute' + query, {
      method:'POST', credentials:'same-origin',
      headers:{Accept:'application/json','Content-Type':'application/json','X-CSRF-Token':host.dataset.csrfToken},
      body:JSON.stringify(request)
    });
    const data = await window.nevaeh.parseResponse(response);
    if (data.status !== 'completed') throw Error(data.error || 'Studio could not complete this action.');
    return rewrite(data.result);
  }
  async function upload(file, key = requestKey()) {
    const body = new FormData();
    body.append('file',file);
    body.append('purpose','studio_asset');
    const response = await fetch(host ? prefix + '/uploads' + query : '/api/lightek/pwa/uploads', {
      method:'POST',credentials:'same-origin',
      headers:host ? {'X-CSRF-Token':host.dataset.csrfToken,Accept:'application/json'} : window.nevaeh.csrfHeaders(),
      body
    });
    const data = await window.nevaeh.parseResponse(response);
    return call('asset.import',{signed_id:data.signed_id,name:file.name.slice(0,160),request_key:key});
  }
  return {call,upload,dashboard:!!host,site,advanced:scene => {
    const params = new URLSearchParams({advanced:'1',workspace:'edit'});
    if (site) params.set('site_id',site);
    return prefix + '/workspace/' + scene + '?' + params;
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
