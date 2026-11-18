/* Membership checkout uses the existing verified commerce lifecycle. */
(() => {
  let data = null, error = '', loading = false, busy = false;
  const esc = v => E(String(v ?? ''));
  const hostingState = state => ({queued:'Preparing your account',provisioning:'Preparing your account',shared_ready:'Ready',dedicated_ready:'Ready',migrating:'Moving to dedicated hosting',moving_content:'Moving to dedicated hosting',failed:'Setup needs attention',retired:'Retired'})[state] || String(state || 'Preparing').replaceAll('_',' ');
  const money = cents => new Intl.NumberFormat(undefined,{style:'currency',currency:'USD'}).format(cents/100);
  async function request(path = '', body) {
    const response = await fetch('/api/lightek/pwa/membership' + path, {
      method: body ? 'POST' : 'GET', credentials: 'same-origin',
      headers: {...window.nevaeh.csrfHeaders(), Accept:'application/json', ...(body ? {'Content-Type':'application/json'} : {})},
      ...(body ? {body:JSON.stringify(body)} : {})
    });
    return window.nevaeh.parseResponse(response);
  }
  async function load(force = false) {
    if (loading || (data && !force)) return;
    loading = true; error = '';
    try { data = await request(); } catch(e) { error = e.message; }
    loading = false;
    if(location.hash.startsWith('#/membership')) render(1);
  }
  R.membership = result => `<div class="wrap pwa-page"><header class="ah"><div><span class="eb">LIGHTEK MEMBERSHIP</span><h1>Your space. Your server.</h1><p>Start free with shared hosting. Upgrade to dedicated hosting for your own instance.</p></div><button class="btn sm" data-a="membershipRefresh">Refresh status</button></header>
    ${result === 'processing' ? '<p class="pwa-empty" role="status">Confirming payment and preparing your instance. This page does not activate a membership by itself. Refresh status for the latest result.</p>' : result === 'canceled' ? '<p class="pwa-empty">Checkout canceled. No new membership has been activated here.</p>' : ''}
    ${error ? `<p role="alert" class="pwa-empty">${esc(error)}</p>` : ''}
    ${!data ? '<p role="status">Loading membership…</p>' : `<p>Current plan: <strong>${esc(data.current_plan)}</strong>${data.current_period_end ? ' · Paid through '+esc(new Date(data.current_period_end).toLocaleDateString()) : ''}${data.cancel_at_period_end ? ' · Renewal canceled' : ''}</p>
    ${me()&&(data.backend||data.current_plan==='community')?`<section class="pwa-post"><h2>My publishing space</h2>${data.backend?`<p>${esc(hostingState(data.backend.state))} · ${esc(data.backend.mode==='shared'?'Shared hosting — free account':'Dedicated hosting')}</p>${data.backend.ready?'<button class="btn p" data-a="membershipOpenBackend">Create a post</button>':`<p role="status">${data.backend.state==='migrating'?'Moving and verifying your account on dedicated hosting.':'Preparing your shared hosting account.'} You can keep browsing while setup finishes.</p>`}`:'<p>Your free account shares a Lightek instance on the free-member server.</p><button class="btn" data-a="membershipPrepareBackend">Prepare my space</button>'}</section>`:''}
    ${data.installation ? `<section class="pwa-post"><h2>My instance</h2><p>${esc(hostingState(data.installation.state))} · ${esc(data.installation.hostname)}</p>${data.installation.ready ? `<a class="btn p" href="${esc(data.installation.url)}/lightek/index.html#/home">Open my PWA</a>` : ''}<a class="btn" href="${esc(data.installation_path)}">${data.installation.ready?'Manage instance & sign-in':'View setup progress'}</a></section>` : ''}
    <div class="pwa-plan-grid">${data.plans.map(p=>`<section class="pwa-post pwa-plan"><span class="eb">${esc(p.name)}</span><h2>${p.price_cents == null ? 'Package not open' : p.price_cents === 0 ? 'Free' : money(p.price_cents)+'<small> / month</small>'}</h2><ul>${p.features.map(f=>`<li>${esc(f)}</li>`).join('')}</ul>${me() && p.key === data.current_plan ? '<span class="btn">Current plan</span>' : p.key === 'community' ? `<a class="btn" href="${me()?'#/home':'/sign_up?return_to='+encodeURIComponent('/lightek/index.html#/home')}">${me()?'Open community':'Join free'}</a>` : !me() ? `<a class="btn" href="${esc(signInHref('#/membership'))}">Sign in to upgrade</a>` : `<button class="btn p" data-a="membershipBuy" data-plan="${esc(p.key)}" ${busy||!p.available||data.current_plan!=='community'?'disabled':''}>${p.available?'Get my instance':'Not open yet'}</button>`}</section>`).join('')}</div>
    <p>${esc(data.setup_note)}</p><p>Applicable tax is shown before payment. YouTube videos remain free to watch; membership pays for your Lightek instance. Business includes the agency account; each client server package is billed separately. Business agency access activates after verified payment.</p>
    ${data.current_plan !== 'community' && !data.cancel_at_period_end ? '<details class="pwa-post"><summary>Cancel automatic renewal</summary><p>Your paid period continues until its end. Review your instance and export your content before the service ends.</p><button class="btn" data-a="membershipCancel">Confirm cancellation of renewal</button></details>' : ''}
    ${me()?`<section class="pwa-post"><h2>My Lightek email</h2>${data.email?.address?`<p>${esc(data.email.address)}</p><a class="btn" href="/dashboard/mail">Open inbox</a>`:`<p>Use your own Lightek address. Confirm your signup email before creating an inbox.</p><button class="btn" data-a="membershipEmail" ${!data.email?.open?'disabled':''}>${data.email?.open?'Create my Lightek inbox':'Member email is not open yet'}</button>`}<p>Business / Agency can also use verified custom domains.</p></section>`:''}
    ${me()?`<section class="pwa-post"><h2>Finalized view earnings</h2><p>Actual finalized channel proceeds determine your earnings per 1,000 eligible views. Available earnings have verified funding. Released means credited to your payout account; bank delivery follows its payout schedule.</p>${(data.view_earnings||[]).map(row=>`<p>${esc(row.video_id)} · ${esc(row.month)} · ${money(row.amount_cents)} · ${esc(row.state)}${row.earnings_per_thousand_views_cents==null?'':' · '+money(row.earnings_per_thousand_views_cents)+' per 1,000 views'} ${data.view_payouts_open&&['available','transfer_pending'].includes(row.state)&&row.amount_cents>0?`<button class="btn sm" data-a="membershipReleaseViews" data-id="${Number(row.id)}">Release earnings</button>`:''}</p>`).join('')||'<p>No finalized view earnings yet.</p>'}<a class="btn" href="/dashboard/susu/payout-account">Set up payouts</a></section>`:''}
    ${me()?`<section class="pwa-post"><h2>YouTube revenue reports</h2><p>Your estimated earnings from views of your videos on the Lightek YouTube channel. The rate varies with actual reported revenue; it is not a guaranteed payment for each view. These are not withdrawable funds. YouTube pays Lightek; creator payouts require reconciliation and confirmed funding.</p>${(data.youtube_revenue||[]).map(row=>`<p>${esc(row.video_id)} · ${esc(row.period_start)}–${esc(row.period_end)} · ${Number(row.views).toLocaleString()} views · ${money(row.creator_cents)} estimated earnings${row.earnings_per_thousand_views_cents==null?'':' · '+money(row.earnings_per_thousand_views_cents)+' per 1,000 views'}</p>`).join('')||'<p>No revenue reports recorded yet.</p>'}<details><summary>How view earnings are calculated</summary><p>The creator receives 80% of the channel revenue attributable to eligible paid-member videos after YouTube’s share; Lightek retains 20%. Sharing begins with the first complete YouTube reporting day within a verified paid period. Earnings per 1,000 views are calculated from reported creator earnings and views. Estimates become payable only after final reconciliation and funding.</p></details></section>`:''}`}</div>`;
  AF.membership = () => load();
  A.membershipRefresh = () => {data=null;load(true);};
  A.membershipBuy = async button => {
    if(busy)return;busy=true;error='';render(1);
    try { const result=await request('/checkout',{plan:button.dataset.plan});
      const url=new URL(result.checkout_url);
      if(url.protocol!=='https:')throw new Error('Checkout did not return a secure destination');
      location.assign(url.href);
    }catch(e){error=e.message;busy=false;render(1);}
  };
  async function backendRequest(action) {
    const response=await fetch('/api/lightek/pwa/member-backend'+action,{method:'POST',credentials:'same-origin',headers:{...window.nevaeh.csrfHeaders(),Accept:'application/json'}});
    return window.nevaeh.parseResponse(response);
  }
  A.membershipPrepareBackend=async()=>{try{await backendRequest('');await load(true);}catch(e){error=e.message;render(1);}};
  A.membershipOpenBackend=async()=>{try{const result=await backendRequest('/open');const url=new URL(result.url);if(url.protocol!=='https:'||url.host!==data.backend.hostname||url.pathname!=='/pwa/member-session')throw new Error('Invalid member destination');location.assign(url.href);}catch(e){error=e.message;render(1);}};
  A.membershipReleaseViews=async button=>{if(busy)return;busy=true;try{data=await request('/view-earnings/'+Number(button.dataset.id)+'/release',{});}catch(e){error=e.message;}busy=false;render(1);};
  A.membershipEmail = async () => {try{const response=await fetch('/api/lightek/pwa/member-email',{method:'POST',credentials:'same-origin',headers:window.nevaeh.csrfHeaders()});const result=await window.nevaeh.parseResponse(response);toast(result.message);}catch(e){error=e.message;render(1);}};
  A.membershipCancel = async () => {if(busy)return;busy=true;try{data=await request('/cancel',{});}catch(e){error=e.message;}busy=false;render(1);};

  R.services = () => {
    const bootstrap=window.LightekStorefront?.state.bootstrap||{};
    const links=[...(bootstrap.navigation||[]).filter(n=>n.enabled!==false),...(bootstrap.services||[])];
    const seen=new Set();
    return `<div class="wrap pwa-page"><h1>More from Lightek</h1><p>Choose what you want to do.</p><div class="pwa-services"><a class="btn p" href="#/membership">Membership & my instance</a>${meProfile()?.id?`<a class="btn" href="#/support/${Number(meProfile().id)}">Creator earnings & support</a>`:''}${links.filter(item=>item.href&&!seen.has(item.href)&&seen.add(item.href)).map(item=>`<a class="btn" href="${esc(item.href)}">${esc(item.label||item.key)}</a>`).join('')}${me()?'<a class="btn" href="/my/installations">My Applications</a>':''}</div></div>`;
  };
  A.openPublishingStudio = async () => {
    try {
      const response=await fetch('/api/lightek/pwa/member-backend',{credentials:'same-origin',headers:{Accept:'application/json'}});
      const status=await window.nevaeh.parseResponse(response);
      if(!status.backend?.ready)throw new Error('Your publishing space is preparing. Open Membership for status.');
      const result=await backendRequest('/open'),url=new URL(result.url);
      if(url.protocol!=='https:'||url.host!==status.backend.hostname||url.pathname!=='/pwa/member-session')throw new Error('Invalid publishing destination');
      url.searchParams.set('workspace','studio');location.assign(url.href);
    } catch(e) {toast(e.message);}
  };
  function studioPublishingGateway(){
    if(typeof R.studio!=='function'||R.studio.memberGateway)return;
    const prior=R.studio;
    const guarded=id=>{
      const destination=window.LightekStorefront?.state.bootstrap?.publishing;
      if(!destination|| (id&&!['create','templates','library'].includes(String(id))))return prior(id);
      document.body?.classList?.remove('lt-visual');
      const action=destination.member_backend?'<button class="btn p" data-a="openPublishingStudio">Open my Studio</button>':
        destination.ready&&destination.create_url?'<a class="btn p" href="'+esc(destination.create_url.replace('#/create','#/studio'))+'">Open my Studio</a>':'';
      return '<div class="wrap pwa-page"><h1>Studio in your publishing space</h1><p>New projects, media and processing run on your member server. Your shared space moves with you when you upgrade.</p>'+action+'<a class="btn" href="'+esc(destination.manage_url)+'">Membership & setup status</a><p>Historical projects here remain readable. Start new work in your publishing space.</p></div>';
    };
    guarded.memberGateway=true;R.studio=guarded;
  }
  addEventListener('lightek.bootstrap.ready',studioPublishingGateway);
  function communityOrigin(){
    const source=window.LightekStorefront?.state.bootstrap?.member_source;
    if(!source?.origin)return null;
    try {
      const url=new URL(source.origin);
      return url.protocol==='https:'&&url.pathname==='/'&&!url.username&&!url.password&&!url.search&&!url.hash ? url.origin : null;
    } catch (_) {
      return null;
    }
  }
  function simplifyNavigation(){
    const primary=document.querySelector('#primary-nav'),tools=document.querySelector('#top .tools');
    const origin=communityOrigin(),home=origin?`${origin}/lightek/index.html#/home`:'#/home';
    const studio=document.querySelector('#app');
    if(studio){
      let exit=document.querySelector('#studio-app-exit');
      if(!exit){
        exit=document.createElement('a');exit.id='studio-app-exit';
        studio.before(exit);
      }
      exit.textContent='← Back to app';
      exit.setAttribute('href',home);
    }
    if(origin){
      if(primary)primary.innerHTML=`<a href="${esc(home)}">Back to community</a><a href="#/create">Create</a><a href="#/studio">Studio</a><a href="#/space">My posts</a>`;
      if(tools&&!tools.querySelector('[data-member-central]'))tools.insertAdjacentHTML('beforeend',`<a class="hd2" data-member-central href="${esc(origin)}/lightek/index.html#/membership">Membership & earnings</a>`);
      return;
    }
    if(primary)for(const link of [...primary.querySelectorAll('a')].slice(5))link.remove();
    if(tools){tools.querySelector('[data-installations-link]')?.remove();if(!tools.querySelector('[data-pwa-more]'))tools.insertAdjacentHTML('beforeend','<a class="hd2" href="#/services" data-pwa-more>More</a>');}
  }
  addEventListener('lightek.bootstrap.ready',simplifyNavigation);
  addEventListener('lightek.bootstrap.ready',()=>{data=null;});
})();
