(() => {
  document.documentElement.classList.add("dd-enhanced");
  function setupDashboardNavigation() {
    const button = document.querySelector('[data-dashboard-menu]');
    const sidebar = document.getElementById('dd-primary-navigation');
    const scrim = document.querySelector('[data-dashboard-menu-close]');
    if (!button || !sidebar || !scrim || button.dataset.ready) return;
    button.dataset.ready = 'true';
    const listeners = new AbortController();
    const eventOptions = {signal: listeners.signal};
    const mobile = window.matchMedia('(max-width: 768px)');
    const setOpen = (open, restoreFocus = false) => {
      sidebar.classList.toggle('open', open);
      button.setAttribute('aria-expanded', String(open));
      button.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
      scrim.hidden = !open;
      sidebar.inert = mobile.matches && !open;
      if (open) sidebar.querySelector('a')?.focus();
      else if (restoreFocus) button.focus();
    };
    button.addEventListener('click', () => setOpen(button.getAttribute('aria-expanded') !== 'true'), eventOptions);
    scrim.addEventListener('click', () => setOpen(false, true), eventOptions);
    sidebar.addEventListener('click', event => { if (mobile.matches && event.target.closest('a')) setOpen(false); }, eventOptions);
    const onKeydown = event => {
      if (button.getAttribute('aria-expanded') !== 'true') return;
      if (event.key === 'Escape') { setOpen(false, true); return; }
      if (event.key !== 'Tab') return;
      const links = [...sidebar.querySelectorAll('a[href], button:not([disabled]), summary')].filter(link => link.getClientRects().length);
      if (!links.length) return;
      const first = links[0], last = links[links.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    };
    document.addEventListener('keydown', onKeydown);
    const onChange = () => setOpen(false);
    mobile.addEventListener('change', onChange);
    document.addEventListener('turbo:before-cache', () => {
      setOpen(false);
      mobile.removeEventListener('change', onChange);
      document.removeEventListener('keydown', onKeydown);
      listeners.abort();
      delete button.dataset.ready;
    }, {once: true});
    setOpen(false);
  }
  document.addEventListener('click', event => {
    const link = event.target.closest('[data-dns-edit]');
    if (!link) return;
    const editor = document.getElementById(link.dataset.dnsEdit);
    if (!editor) return;
    event.preventDefault();
    editor.open = !editor.open;
    link.setAttribute('aria-expanded', String(editor.open));
    if (editor.open) editor.querySelector('input:not([type=hidden])')?.focus();
  });
  document.addEventListener('toggle', event => {
    if (!event.target.matches('.net-dns-editor')) return;
    for (const link of document.querySelectorAll('[data-dns-edit]')) {
      if (link.dataset.dnsEdit === event.target.id) link.setAttribute('aria-expanded', String(event.target.open));
    }
  }, true);
  document.addEventListener('input', event => {
    if (!event.target.matches('.dd-color-field input[type=color]')) return;
    const label = event.target.parentElement.querySelector('[data-color-value]');
    if (label) label.textContent = event.target.value;
  });
  document.addEventListener('DOMContentLoaded', setupDashboardNavigation);
  document.addEventListener('turbo:load', setupDashboardNavigation);
  setupDashboardNavigation();
})();
