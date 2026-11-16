(() => {
  document.documentElement.classList.add("dd-enhanced");
  function setupToolSearch() {
    const input = document.querySelector('[data-tool-search]');
    if (!input || input.dataset.ready) return;
    input.dataset.ready = 'true';
    input.closest('[data-navigation-search]').hidden = false;
    const groups = [...document.querySelectorAll('[data-tool-group]')];
    const empty = document.querySelector('[data-tool-empty]');
    let previous = null;
    const filter = () => {
      const query = input.value.trim().toLocaleLowerCase();
      if (query && !previous) previous = groups.map(group => group.open);
      let matches = 0;
      groups.forEach((group, index) => {
        let count = 0;
        group.querySelectorAll('[data-tool-link]').forEach(link => {
          const found = !query || link.textContent.toLocaleLowerCase().includes(query);
          link.hidden = !found;
          if (found) count++;
        });
        group.hidden = count === 0;
        matches += count;
        if (query) group.open = count > 0;
        else if (previous) group.open = previous[index];
      });
      if (!query) previous = null;
      if (empty) empty.hidden = matches > 0;
    };
    const onKey = event => {
      if (event.key === 'Escape' && input.value) {
        event.stopPropagation();
        input.value = '';
        filter();
      }
    };
    input.addEventListener('input', filter);
    input.addEventListener('keydown', onKey);
    document.addEventListener('turbo:before-cache', () => {
      input.value = '';
      filter();
      input.removeEventListener('input', filter);
      input.removeEventListener('keydown', onKey);
      delete input.dataset.ready;
    }, {once: true});
    filter();
  }
  document.addEventListener('DOMContentLoaded', setupToolSearch);
  document.addEventListener('turbo:load', setupToolSearch);
  setupToolSearch();
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
  function updateOrderSelection(workspace) {
    if (!workspace) return;
    const choices = [...workspace.querySelectorAll('[data-order-select]')];
    const selected = choices.filter(choice => choice.checked);
    const all = workspace.querySelector('[data-order-select-all]');
    const count = workspace.querySelector('[data-order-selection-count]');
    const submit = workspace.querySelector('[data-order-bulk-delete]');
    workspace.querySelector('[data-order-selection-tools]')?.removeAttribute('hidden');
    if (all) {
      all.checked = choices.length > 0 && selected.length === choices.length;
      all.indeterminate = selected.length > 0 && selected.length < choices.length;
    }
    if (count) count.textContent = selected.length ? `${selected.length} unpaid order${selected.length === 1 ? '' : 's'} selected` : 'Select unpaid orders to clean up';
    if (submit) submit.disabled = selected.length === 0;
    choices.forEach(choice => choice.closest('.dd-order')?.classList.toggle('is-selected', choice.checked));
  }
  function setupOrderSelection() {
    document.querySelectorAll('[data-orders-workspace]').forEach(updateOrderSelection);
  }
  document.addEventListener('change', event => {
    if (!event.target.matches('[data-order-select], [data-order-select-all]')) return;
    const workspace = event.target.closest('[data-orders-workspace]');
    if (event.target.matches('[data-order-select-all]')) {
      workspace?.querySelectorAll('[data-order-select]').forEach(choice => { choice.checked = event.target.checked; });
    }
    updateOrderSelection(workspace);
  });
  document.addEventListener('DOMContentLoaded', setupOrderSelection);
  document.addEventListener('turbo:load', setupOrderSelection);
  setupOrderSelection();
  document.addEventListener('DOMContentLoaded', setupDashboardNavigation);
  document.addEventListener('turbo:load', setupDashboardNavigation);
  setupDashboardNavigation();
})();
