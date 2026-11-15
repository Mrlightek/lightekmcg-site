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
      const timeout = setTimeout(() => reject(new Error('load')), 15000);
      const loaded = () => { if (window.StripeConnect?.init) { clearTimeout(timeout); resolve(window.StripeConnect); } };
      window.StripeConnect = window.StripeConnect || {};
      window.StripeConnect.onLoad = loaded;
      script.onload = loaded;
      script.onerror = () => { clearTimeout(timeout); reject(new Error('load')); };
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
    const messages = {
      connection_unavailable: 'Your saved payout connection cannot be accessed. Refresh this page to review connection repair. Existing balances are not moved by repair.',
      embedded_configuration: 'Embedded fields are awaiting platform configuration. Use Open secure verification below to continue.',
      configuration_missing: 'Payout setup needs platform configuration. Contact your platform administrator.',
      session_expired: 'Sign in again and verify your authentication code to continue payout setup.',
      verification_unavailable: 'Payout verification is unavailable. Retry or ask your platform administrator to check account access.',
      load: 'Secure fields could not load in this browser. Use Open secure verification below to continue.'
    };
    function handleError(error) {
      showError(messages[error.message] || messages.verification_unavailable);
      if (error.message === 'connection_unavailable') {
        opens.forEach(button => { button.disabled = true; });
        root.dataset.payoutState = 'unavailable';
      }
    }
    async function request(url, options = {}) {
      const response = await fetch(url, {credentials: 'same-origin', cache: 'no-store', redirect: 'error', ...options});
      const type = response.headers.get('content-type') || '';
      if (!type.includes('application/json')) throw new Error('session_expired');
      const data = await response.json();
      if (!response.ok) throw new Error(response.status === 401 || response.status === 403 ? 'session_expired' : Object.hasOwn(messages, data.code) ? data.code : 'verification_unavailable');
      return data;
    }
    async function refresh() {
      const data = await request(root.dataset.statusUrl);
      output.hidden = true;
      // Re-render server-authorized actions when account access changes. Never
      // keep offering setup against an account the server cannot access.
      if ((data.state === 'unavailable') !== (root.dataset.payoutState === 'unavailable')) {
        location.reload();
        return data;
      }
      const ready = data.state === 'ready';
      const badge = root.querySelector('[data-payout-badge]');
      badge.textContent = ready ? 'Ready for payouts' : 'Verification required';
      badge.dataset.tone = ready ? 'success' : 'warning';
      root.querySelector('[data-payout-status]').textContent = data.state === 'unavailable' ? (data.replaceable ? messages.connection_unavailable : messages[data.code] || messages.verification_unavailable) : ready ? 'Your account was verified and is enabled to receive payouts.' : data.state === 'pending_verification' ? 'Your information is under review. Check setup for outstanding requirements.' : 'Your payout connection needs attention. Open setup to complete verification, or contact your account administrator.';
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
        // Fetch only after a deliberate user action. Session refresh stays bound
        // to the signed-in owner and is reauthorized on every server request.
        let session = await postSession(component);
        const provider = await loadProvider();
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
        element.setOnLoadError?.(() => handleError(new Error('load')));
        element.setOnExit?.(() => refresh().catch(() => showError('We could not refresh verification. Refresh status before requesting earnings.')));
        container.replaceChildren(element);
      } catch (error) {
        // Display only locally defined messages; raw provider/server errors
        // can contain credentials or financial account identifiers.
        handleError(error);
      } finally {busy = false; opens.forEach(button => { button.disabled = root.dataset.payoutState === 'unavailable'; });}
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
