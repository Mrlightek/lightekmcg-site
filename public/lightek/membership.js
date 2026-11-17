/* Membership checkout uses the existing verified commerce lifecycle. */
(() => {
  let data = null, error = '', loading = false, busy = false;
  const esc = v => E(String(v ?? ''));
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
  R.membership = result => `<div class="wrap pwa-page"><header class="ah"><div><span class="eb">LIGHTEK MEMBERSHIP</span><h1>Your space. Your server.</h1><p>Join the community free. Upgrade for your own backend and content storage.</p></div><button class="btn sm" data-a="membershipRefresh">Refresh status</button></header>
    ${result === 'processing' ? '<p class="pwa-empty" role="status">Confirming payment and preparing your instance. This page does not activate a membership by itself. Refresh status for the latest result.</p>' : result === 'canceled' ? '<p class="pwa-empty">Checkout canceled. No new membership has been activated here.</p>' : ''}
    ${error ? `<p role="alert" class="pwa-empty">${esc(error)}</p>` : ''}
    ${!data ? '<p role="status">Loading membership…</p>' : `<p>Current plan: <strong>${esc(data.current_plan)}</strong>${data.current_period_end ? ' · Paid through '+esc(new Date(data.current_period_end).toLocaleDateString()) : ''}${data.cancel_at_period_end ? ' · Renewal canceled' : ''}</p>
    ${data.installation ? `<section class="pwa-post"><h2>My instance</h2><p>${esc(data.installation.state)} · ${esc(data.installation.hostname)}</p>${data.installation.ready ? `<a class="btn p" href="${esc(data.installation.url)}/lightek/index.html#/home">Open my PWA</a>` : ''}<a class="btn" href="${esc(data.installation_path)}">${data.installation.ready?'Manage instance & sign-in':'View setup progress'}</a></section>` : ''}
    <div class="pwa-plan-grid">${data.plans.map(p=>`<section class="pwa-post pwa-plan"><span class="eb">${esc(p.name)}</span><h2>${p.price_cents == null ? 'Package not open' : p.price_cents === 0 ? 'Free' : money(p.price_cents)+'<small> / month</small>'}</h2><ul>${p.features.map(f=>`<li>${esc(f)}</li>`).join('')}</ul>${me() && p.key === data.current_plan ? '<span class="btn">Current plan</span>' : p.key === 'community' ? `<a class="btn" href="${me()?'#/home':'/sign_up?return_to='+encodeURIComponent('/lightek/index.html#/home')}">${me()?'Open community':'Join free'}</a>` : !me() ? `<a class="btn" href="${esc(signInHref('#/membership'))}">Sign in to upgrade</a>` : `<button class="btn p" data-a="membershipBuy" data-plan="${esc(p.key)}" ${busy||!p.available||data.current_plan!=='community'?'disabled':''}>${p.available?'Get my instance':'Not open yet'}</button>`}</section>`).join('')}</div>
    <p>${esc(data.setup_note)}</p><p>Applicable tax is shown before payment. YouTube videos remain free to watch; membership pays for your Lightek instance. Business includes the agency account; each client server package is billed separately. Business agency access activates after verified payment.</p>
    ${data.current_plan !== 'community' && !data.cancel_at_period_end ? '<details class="pwa-post"><summary>Cancel automatic renewal</summary><p>Your paid period continues until its end. Review your instance and export your content before the service ends.</p><button class="btn" data-a="membershipCancel">Confirm cancellation of renewal</button></details>' : ''}
    ${me()?`<section class="pwa-post"><h2>My Lightek email</h2>${data.email?.address?`<p>${esc(data.email.address)}</p><a class="btn" href="/dashboard/mail">Open inbox</a>`:`<p>Use your own Lightek address. Confirm your signup email before creating an inbox.</p><button class="btn" data-a="membershipEmail" ${!data.email?.open?'disabled':''}>${data.email?.open?'Create my Lightek inbox':'Member email is not open yet'}</button>`}<p>Business / Agency can also use verified custom domains.</p></section>`:''}
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
  A.membershipEmail = async () => {try{const response=await fetch('/api/lightek/pwa/member-email',{method:'POST',credentials:'same-origin',headers:window.nevaeh.csrfHeaders()});const result=await window.nevaeh.parseResponse(response);toast(result.message);}catch(e){error=e.message;render(1);}};
  A.membershipCancel = async () => {if(busy)return;busy=true;try{data=await request('/cancel',{});}catch(e){error=e.message;}busy=false;render(1);};

  R.services = () => {
    const bootstrap=window.LightekStorefront?.state.bootstrap||{};
    const links=[...(bootstrap.navigation||[]).filter(n=>n.enabled!==false),...(bootstrap.services||[])];
    const seen=new Set();
    return `<div class="wrap pwa-page"><h1>More from Lightek</h1><p>Choose what you want to do.</p><div class="pwa-services"><a class="btn p" href="#/membership">Membership & my instance</a>${meProfile()?.id?`<a class="btn" href="#/support/${Number(meProfile().id)}">Creator earnings & support</a>`:''}${links.filter(item=>item.href&&!seen.has(item.href)&&seen.add(item.href)).map(item=>`<a class="btn" href="${esc(item.href)}">${esc(item.label||item.key)}</a>`).join('')}${me()?'<a class="btn" href="/my/installations">My Applications</a>':''}</div></div>`;
  };
  function simplifyNavigation(){
    const primary=document.querySelector('#primary-nav'),tools=document.querySelector('#top .tools');
    if(primary)for(const link of [...primary.querySelectorAll('a')].slice(5))link.remove();
    if(tools){tools.querySelector('[data-installations-link]')?.remove();if(!tools.querySelector('[data-pwa-more]'))tools.insertAdjacentHTML('beforeend','<a class="hd2" href="#/services" data-pwa-more>More</a>');}
  }
  addEventListener('lightek.bootstrap.ready',simplifyNavigation);
  addEventListener('lightek.bootstrap.ready',()=>{data=null;});
})();
