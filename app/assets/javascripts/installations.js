(() => {
  const panel = document.querySelector('[data-installation-status-url]');
  if (!panel || ['ready', 'failed', 'awaiting_dns', 'canceled', 'refunded', 'partially_refunded'].includes(panel.dataset.installationState)) return;
  let stopped = false;
  window.addEventListener('pagehide', () => { stopped = true; });
  async function poll() {
    if (stopped) return;
    if (!document.hidden) {
      try {
        const response = await fetch(panel.dataset.installationStatusUrl, {credentials: 'same-origin', cache: 'no-store', headers: {'Accept': 'application/json'}});
        if (response.status === 401 || response.redirected) { stopped = true; return; }
        if (response.ok) {
          const state = await response.json();
          if (state.state !== panel.dataset.installationState || (state.dns_record && !panel.querySelector('[data-installation-dns-record]'))) { window.location.reload(); return; }
        }
      } catch (_) {
        const message = panel.querySelector('[data-installation-poll-message]');
        if (message) message.textContent = 'Reconnecting to your installation status. You can safely refresh this page.';
      }
    }
    if (!stopped) window.setTimeout(poll, 5000);
  }
  window.setTimeout(poll, 5000);
})();
