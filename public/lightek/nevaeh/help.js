(() => {
  if (window.lightekContextualHelpInstalled) return;
  window.lightekContextualHelpInstalled = true;

  const dialogSelector = '[data-nevaeh-help-dialog]';
  let activeRequest;
  let observedContent;

  function localLink(path) {
    if (typeof path !== 'string' || !path.startsWith('/')) return null;
    const url = new URL(path, location.origin);
    return url.origin === location.origin ? url : null;
  }

  function cancelRequest() {
    activeRequest?.abort();
    activeRequest = null;
  }

  async function openGuide(dialog, button) {
    cancelRequest();
    const request = new AbortController();
    activeRequest = request;
    const title = dialog.querySelector('#nv-help-title');
    const body = dialog.querySelector('[data-nevaeh-help-body]');
    const link = dialog.querySelector('[data-nevaeh-help-document]');
    title.textContent = 'Loading guide…';
    body.replaceChildren();
    link.hidden = true;
    if (!dialog.open) dialog.showModal();

    const current = () => activeRequest === request && dialog.isConnected && dialog.open;
    try {
      const topic = button.dataset.nevaehHelp;
      const useTopic = topic !== 'page' && dialog.dataset.topicEndpoint;
      const endpoint = useTopic
        ? dialog.dataset.topicEndpoint.replace('TOPIC', encodeURIComponent(topic))
        : dialog.dataset.pageEndpoint;
      const url = new URL(endpoint, location.origin);
      if (!useTopic) url.searchParams.set('page', location.pathname);
      if (button.dataset.nevaehField) url.searchParams.set('field', button.dataset.nevaehField);
      const response = await fetch(url, {
        credentials: 'same-origin',
        headers: { Accept: 'application/json' },
        signal: request.signal
      });
      if (!response.ok || response.redirected) throw new Error('Could not load guide');
      const guide = await response.json();
      if (!current()) return;
      title.textContent = guide.title;
      const paragraph = document.createElement('p');
      paragraph.textContent = guide.body;
      body.append(paragraph);
      for (const doc of guide.related_documents || []) {
        const destination = localLink(doc.url);
        if (!destination) continue;
        const anchor = document.createElement('a');
        anchor.href = destination.href;
        anchor.textContent = doc.title;
        body.append(anchor);
      }
      const destination = localLink(guide.document_url);
      if (destination) {
        link.href = destination.href;
        link.hidden = false;
      }
    } catch (error) {
      if (!current() || error.name === 'AbortError') return;
      title.textContent = 'Guide unavailable';
      body.textContent = 'Close the guide and try again. If your session expired, sign in to reopen it.';
    } finally {
      if (activeRequest === request) activeRequest = null;
    }
  }

  document.addEventListener('click', event => {
    const dialog = document.querySelector(dialogSelector);
    if (!dialog) return;
    if (event.target.closest('[data-nevaeh-help-close]')?.closest(dialogSelector) === dialog) {
      dialog.close();
      return;
    }
    const button = event.target.closest('[data-nevaeh-help]');
    if (!button) return;
    event.preventDefault();
    event.stopPropagation();
    openGuide(dialog, button);
  });

  document.addEventListener('close', event => {
    if (event.target === document.querySelector(dialogSelector) && !event.target.open) cancelRequest();
  }, true);

  function attachButtons() {
    if (!observedContent) return;
    const activeTab = observedContent.querySelector('[data-nevaeh-center] .nc-tabs a.active');
    const tabTopic = activeTab && new URL(activeTab.href).searchParams.get('tab');
    for (const label of observedContent.querySelectorAll('label')) {
      if (label.closest('[data-no-help], dialog') || label.querySelector('[data-nevaeh-help]') ||
          label.nextElementSibling?.matches('[data-nevaeh-field]')) continue;
      const control = label.control;
      if (!control?.matches('input:not([type=hidden]), textarea, select')) continue;
      const topic = label.closest('[data-help-scope]')?.dataset.helpScope
        || tabTopic;
      const field = (label.firstChild?.textContent.trim() || label.textContent.trim() || control.name || 'Field').slice(0, 120);
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'nv-info';
      button.textContent = 'i';
      button.dataset.nevaehHelp = topic || 'page';
      button.dataset.nevaehField = field;
      button.setAttribute('aria-label', `Help with ${field}`);
      button.setAttribute('aria-haspopup', 'dialog');
      if (label.contains(control)) {
        let anchor = control;
        while (anchor.parentElement !== label) anchor = anchor.parentElement;
        label.insertBefore(button, anchor);
      } else {
        label.after(button);
      }
    }
  }

  const observer = new MutationObserver(attachButtons);
  function refresh() {
    const content = document.querySelector(dialogSelector) && document.querySelector('.dd-content');
    if (content === observedContent) return;
    observer.disconnect();
    observedContent = content;
    if (!content) return;
    attachButtons();
    observer.observe(content, { childList: true, subtree: true });
  }

  document.addEventListener('turbo:before-cache', () => {
    cancelRequest();
    const dialog = document.querySelector(dialogSelector);
    if (dialog?.open) dialog.close();
    observer.disconnect();
    observedContent = null;
  });
  document.addEventListener('DOMContentLoaded', refresh);
  document.addEventListener('turbo:render', refresh);
  document.addEventListener('turbo:load', refresh);
  refresh();
})();
