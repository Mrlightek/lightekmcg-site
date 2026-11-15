(() => {
  // Only short-lived account-session credentials enter this module. No bank,
  // identity or tax fields are read, stored, logged, or posted by this script.
  let loader;
  const accountInstances = new Set();
  function loadProvider() {
    if (window.StripeConnect?.init) return Promise.resolve(window.StripeConnect);
    if (loader) return loader;
    loader = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://connect-js.stripe.com/v1.0/connect.js';
      script.async = true;
      script.onload = () => window.StripeConnect?.init ? resolve(window.StripeConnect) : reject(new Error('load'));
      script.onerror = () => reject(new Error('load'));
      document.head.appendChild(script);
    }).catch(error => { loader = undefined; throw error; });
    return loader;
  }
  function setup() {
    const root = document.querySelector('[data-payout-workspace]');
    if (!root || root.dataset.ready) return;
    root.dataset.ready = 'true';
    const output = root.querySelector('[data-payout-error]');
    const container = root.querySelector('[data-payout-component]');
    const opens = [...root.querySelectorAll('[data-payout-open]')];
    const listeners = new AbortController();
    let instance, busy = false;
    const showError = message => { output.textContent = message; output.hidden = false; };
    async function request(url, options = {}) {
      const response = await fetch(url, {credentials: 'same-origin', cache: 'no-store', redirect: 'error', ...options});
      const type = response.headers.get('content-type') || '';
      if (!type.includes('application/json')) throw new Error('Sign in again to continue secure payout setup.');
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Payout setup is temporarily unavailable. Please try again.');
      return data;
    }
    async function refresh() {
      const data = await request(root.dataset.statusUrl);
      const ready = data.state === 'ready';
      const badge = root.querySelector('[data-payout-badge]');
      badge.textContent = ready ? 'Ready for payouts' : 'Verification required';
      badge.dataset.tone = ready ? 'success' : 'warning';
      root.querySelector('[data-payout-status]').textContent = ready ? 'Your account was verified and is enabled to receive payouts.' : data.state === 'pending_verification' ? 'Your information is under review. Check setup for outstanding requirements.' : 'Your payout connection needs attention. Open setup to complete verification, or contact your account administrator.';
      return data;
    }
    const postSession = component => request(root.dataset.sessionUrl, {
      method: 'POST', headers: {'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || ''},
      body: JSON.stringify({component})
    });
    async function open(component) {
      if (busy) return;
      busy = true; opens.forEach(button => { button.disabled = true; }); output.hidden = true;
      try {
        const provider = await loadProvider();
        // Fetch only after a deliberate user action. Session refresh stays bound
        // to the signed-in owner and is reauthorized on every server request.
        let session = await postSession(component);
        const publicKey = session.publishable_key;
        let firstSecret = session.client_secret;
        session = null;
        if (instance) { container.replaceChildren(); }
        const style = getComputedStyle(document.body);
        instance = provider.init({publishableKey: publicKey, displayOptions: {showObjectIds: false},
          fetchClientSecret: async () => {
            if (firstSecret) { const value = firstSecret; firstSecret = undefined; return value; }
            return (await postSession(component)).client_secret;
          },
          appearance: {overlays: 'dialog', variables: {colorPrimary: style.getPropertyValue('--dd-accent').trim() || '#2563eb',
            colorBackground: style.getPropertyValue('--dd-sidebar-bg').trim() || '#ffffff', colorText: style.getPropertyValue('--dd-text-primary').trim() || '#172033', borderRadius: '10px'}}
        });
        accountInstances.add(instance);
        const element = instance.create(component);
        element.setOnLoadError?.(() => showError('Secure account fields could not load. Please retry or contact support.'));
        element.setOnExit?.(() => refresh().catch(() => showError('We could not refresh verification. Refresh status before requesting earnings.')));
        container.replaceChildren(element);
      } catch (error) {
        // Only our own server returns display-safe error text. Never echo a
        // provider exception, including keys, account IDs or session credentials.
        showError(error.message === 'load' ? 'Secure account fields could not load. Check your connection and retry.' : 'Secure payout setup could not start. Refresh the page or contact your account administrator.');
      } finally {busy = false; opens.forEach(button => { button.disabled = false; });}
    }
    opens.forEach(button => button.addEventListener('click', () => open(button.dataset.payoutOpen), {signal: listeners.signal}));
    root.querySelector('[data-payout-refresh]').addEventListener('click', () => refresh().catch(() => showError('Payout status is unavailable. Sign in again or retry.')), {signal: listeners.signal});
    document.addEventListener('turbo:before-cache', () => {
      container.replaceChildren(); listeners.abort(); instance = undefined; delete root.dataset.ready;
    }, {once: true});
  }
  document.addEventListener('submit', event => {
    const form = event.target;
    const path = new URL(form.action, location.origin).pathname;
    const method = form.querySelector('input[name="_method"]')?.value?.toLowerCase();
    if (method === 'delete' && (path === '/sign_out' || /^\/sessions?\/[^/]+$/.test(path) || path === '/session')) {
      accountInstances.forEach(value => { Promise.resolve(value.logout()).catch(() => {}); });
      accountInstances.clear();
    }
  });
  document.addEventListener('DOMContentLoaded', setup);
  document.addEventListener('turbo:load', setup);
  setup();
})();
