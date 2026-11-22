(() => {
  function boot(root) {
    const panel = root.querySelector('[data-host-cues]');
    if (!panel || panel.dataset.ready) return;
    panel.dataset.ready = 'true';
    const find = (selector) => panel.querySelector(selector);
    const cards = Array.from(panel.querySelectorAll('[data-host-cue]'));
    const previous = find('[data-host-previous]');
    const next = find('[data-host-next]');
    const freestyleButton = find('[data-host-freestyle]');
    const position = find('[data-host-position]');
    let current = 0;
    let freestyle = false;

    function update() {
      cards.forEach((card, index) => { card.hidden = freestyle || index !== current; });
      previous.disabled = freestyle || current === 0;
      next.disabled = freestyle || current === cards.length - 1;
      freestyleButton.textContent = freestyle ? 'Return to rundown' : 'Freestyle';
      freestyleButton.setAttribute('aria-pressed', String(freestyle));
      position.textContent = freestyle ? 'Freestyle · your cue is held' : `Cue ${current + 1} of ${cards.length}`;
    }

    previous.addEventListener('click', () => { current -= 1; update(); });
    next.addEventListener('click', () => { current += 1; update(); });
    freestyleButton.addEventListener('click', () => { freestyle = !freestyle; update(); });
    find('[data-host-navigation]').hidden = false;
    find('[data-host-load]')?.addEventListener('click', () => {
      const apply = root.querySelector('[data-production-apply]');
      const status = find('[data-host-setup-status]');
      const setup = root.querySelector('[data-production-setup]');
      if (root.querySelector('[data-production-scene]').value !== setup.dataset.preparedScene) {
        status.textContent = 'Select the prepared scene in Sources first.';
        return;
      }
      if (apply.disabled) {
        status.textContent = root.querySelector('[data-production-status]').textContent;
        return;
      }
      const notice = root.querySelector('[data-production-status]');
      status.textContent = 'Loading the prepared scene…';
      const observer = new MutationObserver(() => {
        status.textContent = notice.textContent;
        observer.disconnect();
      });
      observer.observe(notice, { childList: true, characterData: true, subtree: true });
      apply.click();
    });
    update();
  }

  const start = () => document.querySelectorAll('[data-live-studio]').forEach(boot);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
  document.addEventListener('turbo:load', start);
})();
