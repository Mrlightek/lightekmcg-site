/* Supporter fees are reviewed before checkout. Only signed payment receipts
   establish gifts, support entitlements or creator earnings. */
(() => {
  let state = {}, busy = false;
  const esc = value => E(String(value ?? ''));
  const money = cents => new Intl.NumberFormat(undefined, {style:'currency', currency:'USD'}).format(Number(cents)/100);
  const myId = () => meProfile()?.id;
  async function api(id, action = '', body) {
    const response = await fetch(`/api/lightek/pwa/creators/${Number(id)}${action}`, {
      method: body ? 'POST' : 'GET', credentials:'same-origin',
      headers:{Accept:'application/json', ...window.nevaeh.csrfHeaders(), ...(body ? {'Content-Type':'application/json'} : {})},
      ...(body ? {body:JSON.stringify(body)} : {})
    });
    return window.nevaeh.parseResponse(response);
  }
  const currentId = () => Number(location.hash.split('/')[2]) || Number(sessionStorage.getItem('lightek-support-creator'));
  const postId = () => Number(location.hash.split('/')[3]) || null;
  async function load() {
    const id = currentId();
    if (!id || state.loading || state.id === id && state.post === postId()) return;
    state = {id, post:postId(), loading:true};
    try {
      state.data = await api(id, state.post ? `?post_id=${state.post}` : '');
      if (Number(myId()) === id) state.earnings = (await api(id, '/earnings')).earnings;
      if(me())state.payments = (await api(id, '/payments')).payments;
    } catch(e) {state.error=e.message;}
    state.loading=false;
    if(location.hash.startsWith('#/support'))render(1);
  }
  R.support = result => {
    const data = state.data, mine = Number(myId()) === state.id;
    return `<div class="wrap pwa-page"><a href="#/home">← Back to community</a><h1>${mine?'Creator earnings':data?`Support ${esc(data.creator.name)}`:'Creator support'}</h1>
    ${result==='processing'?'<p role="status">Checking payment receipts. Your return from checkout does not confirm payment.</p>':result==='canceled'?'<p>Checkout canceled. You can review support options below.</p>':''}
    ${state.error?`<p role="alert">${esc(state.error)}</p>`:''}
    <button class="btn sm" data-a="supportRefresh">Refresh status</button>
    ${data?.subscription_id?`<section class="pwa-post"><p>Monthly support: ${esc(data.subscription_status)}${data.cancel_at_period_end?' · Renewal canceled':''}.</p>${!data.cancel_at_period_end?'<button class="btn" data-a="supportCancel">Cancel monthly renewal</button>':''}</section>`:''}
    ${!data?'<p role="status">Loading…</p>':!me()?`<p><a href="${esc(signInHref(location.hash))}">Sign in</a> to support this creator.</p>`:mine?`
      <section class="pwa-post"><h2>Support settings</h2><p>Free and paid creators keep 100% of subscription, tip and gift principal. Supporters review fees before paying. Gifts display the supporter’s profile name publicly.</p>
      <form data-creator-offer><label class="fld"><span>Monthly creator support (USD)</span><input name="amount" type="number" min="1" max="1000" step="0.01" required value="${esc((data.monthly_cents||500)/100)}"></label><label><input name="enabled" type="checkbox" ${data.offer_enabled?'checked':''}> Accept subscriptions, tips and live gifts</label><button class="btn p" ${data.available?'':'disabled'}>Save settings</button>${!data.available?'<p>Creator support is not open yet. Your existing settings are preserved.</p>':''}</form></section>
      <section class="pwa-post"><h2>Verified support earnings</h2><a class="btn" href="/dashboard/susu/payout-account">Set up payout account</a><p>Available funds can be transferred to your verified payout account. “Transferred” means account credit; bank delivery follows your payout schedule. Refunds or disputes place the related earning on hold.</p>
      ${(state.earnings||[]).map(e=>`<div class="pwa-post"><strong>${money(e.principal_cents)} ${esc(e.kind)}</strong> · ${esc(e.state)}${e.hold_reason?`<p>${esc(e.hold_reason)}</p>`:''}${['held','available','transfer_pending'].includes(e.state)?`<button class="btn sm" data-a="supportRelease" data-id="${Number(e.id)}" ${busy?'disabled':''}>Check funds & release</button>`:''}</div>`).join('')||'<p>No verified earnings yet.</p>'}</section>`:data.enabled?`
      <section class="pwa-post"><p>The creator receives the full amount you select. Support fees and applicable tax are additional. Monthly support renews until canceled. A live gift displays your profile name publicly.</p>
      ${data.subscription_id?'<p>Manage your existing monthly support above.</p>':`<button class="btn p" data-a="supportQuote" data-kind="subscription">Support monthly · ${money(data.monthly_cents)} + fees</button>`}
      <label class="fld"><span>Tip or gift amount (USD)</span><input id="support-amount" type="number" min="1" max="1000" step="0.01" value="5"></label><button class="btn" data-a="supportQuote" data-kind="tip">Review tip</button>${state.post?'<button class="btn" data-a="supportQuote" data-kind="gift">Review live gift</button>':''}
      ${state.quote?`<section class="pwa-post" role="status"><h2>Review your ${esc(state.quote.kind)}</h2><p>Creator receives: <strong>${money(state.quote.principal_cents)}</strong><br>Support fees: ${money(state.quote.fee_cents)}<br>Total before tax: <strong>${money(state.quote.subtotal_cents)}</strong>${state.quote.kind==='subscription'?' each month':''}.</p><p>Applicable tax is shown in secure checkout before payment.</p><button class="btn p" data-a="supportPay" ${busy?'disabled':''}>Continue to secure checkout</button></section>`:''}</section>`:'<p>This creator is not accepting support yet.</p>'}
    ${(state.payments||[]).length?`<section class="pwa-post"><h2>Your payments to this creator</h2>${state.payments.map(p=>`<p>${money(p.principal_cents)} ${esc(p.kind)} · ${esc(p.status)}${p.status==='pending_payment'?` · Support fees ${money(p.fee_cents)} <button class="btn sm" data-a="supportResume" data-id="${Number(p.id)}">Resume secure checkout</button>`:''}${p.confirmed?' · Payment confirmed':''}</p>`).join('')}</section>`:''}
    ${(data?.gifts||[]).length?`<section class="pwa-post"><h2>Confirmed live gifts</h2>${data.gifts.map(g=>`<p>${esc(g.supporter)} sent ${money(g.principal_cents)}</p>`).join('')}</section>`:''}</div>`;
  };
  AF.support = load;
  A.supportRefresh = () => {state={};load();};
  A.supportQuote = async button => {
    if(busy)return;busy=true;
    try {state.quote=await api(state.id,'/quote',{kind:button.dataset.kind, principal_cents:Math.round(Number(document.getElementById('support-amount')?.value||0)*100),post_id:state.post});state.key=crypto.randomUUID();state.error='';}
    catch(e){state.error=e.message;state.quote=null;}
    busy=false;render(1);
  };
  A.supportPay = async () => {
    if(busy||!state.quote)return;busy=true;
    try {const result=await api(state.id,'/checkout',{...state.quote,accepted_fee_cents:state.quote.fee_cents,request_key:state.key});const url=new URL(result.checkout_url);if(url.protocol!=='https:')throw new Error('A secure checkout is required');sessionStorage.setItem('lightek-support-creator',String(state.id));location.assign(url.href);}
    catch(e){state.error=e.message;busy=false;render(1);}
  };
  A.supportResume = async button => {if(busy)return;busy=true;try{const result=await api(state.id,'/resume',{payment_id:Number(button.dataset.id)});const url=new URL(result.checkout_url);if(url.protocol!=='https:')throw new Error('A secure checkout is required');sessionStorage.setItem('lightek-support-creator',String(state.id));location.assign(url.href);}catch(e){state.error=e.message;busy=false;render(1);}};
  A.supportCancel = async () => {try{await api(state.id,'/cancel',{subscription_id:state.data.subscription_id});state={};load();}catch(e){state.error=e.message;render(1);}};
  A.supportRelease = async button => {if(busy)return;busy=true;try{const result=await api(state.id,'/release',{earning_id:Number(button.dataset.id)});toast(result.message);state={};await load();}catch(e){state.error=e.message;}busy=false;render(1);};
  document.addEventListener('submit',async event=>{
    if(!event.target.matches('[data-creator-offer]'))return;event.preventDefault();if(busy)return;busy=true;
    const form=new FormData(event.target);
    try{await api(state.id,'/configure',{monthly_cents:Math.round(Number(form.get('amount'))*100),enabled:form.has('enabled')});state={};await load();toast('Creator support settings saved');}catch(e){state.error=e.message;}
    busy=false;render(1);
  });
  addEventListener('lightek.bootstrap.ready',()=>{state={};});
})();
