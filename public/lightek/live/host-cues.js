(() => {
  const initialized = new WeakSet();

  function boot(root) {
    const panel = root.querySelector('[data-host-cues]');
    if (!panel || initialized.has(panel)) return;
    initialized.add(panel);
    const find = (selector) => panel.querySelector(selector);
    const cards = Array.from(panel.querySelectorAll('[data-host-cue]'));
    const script = find('[data-host-script]');
    const play = find('[data-host-play]');
    const speed = find('[data-host-speed]');
    const textSize = find('[data-host-text-size]');
    const freestyleMessage = find('[data-host-freestyle-message]');
    const previous = find('[data-host-previous]');
    const next = find('[data-host-next]');
    const freestyleButton = find('[data-host-freestyle]');
    const position = find('[data-host-position]');
    let current = 0;
    let freestyle = false;
    let frame = null;
    let lastTime = null;
    let remainder = 0;

    function update() {
      cards.forEach((card, index) => { card.hidden = index !== current; });
      script.toggleAttribute('inert', freestyle);
      script.classList.toggle('ll-host-script-paused', freestyle);
      freestyleMessage.hidden = !freestyle;
      play.disabled = freestyle;
      play.textContent = frame === null ? 'Play scroll' : 'Pause scroll';
      previous.disabled = freestyle || current === 0;
      next.disabled = freestyle || current === cards.length - 1;
      freestyleButton.textContent = freestyle ? 'Return to rundown' : 'Freestyle';
      freestyleButton.setAttribute('aria-pressed', String(freestyle));
      position.textContent = freestyle ? 'Freestyle · your cue is held' : `Cue ${current + 1} of ${cards.length}`;
    }

    function pause() {
      if (frame === null) return;
      cancelAnimationFrame(frame);
      frame = null;
      update();
    }

    function advance(time) {
      const maxScroll = script.scrollHeight - script.clientHeight;
      if (!root.isConnected || document.hidden || script.scrollTop >= maxScroll - 1) {
        pause();
        return;
      }

      if (lastTime !== null) {
        const elapsed = Math.min(time - lastTime, 100);
        const distance = remainder + elapsed * Number(speed.value) / 1000;
        const pixels = Math.floor(distance);
        remainder = distance - pixels;
        script.scrollTop += pixels;
      }
      lastTime = time;
      frame = requestAnimationFrame(advance);
    }

    function selectCue(index) {
      pause();
      current = index;
      update();
      script.scrollTop = 0;
    }

    play.addEventListener('click', () => {
      if (frame !== null) {
        pause();
        return;
      }
      if (script.scrollHeight <= script.clientHeight) {
        position.textContent = `Cue ${current + 1} of ${cards.length} · all text visible`;
        return;
      }
      if (script.scrollTop >= script.scrollHeight - script.clientHeight - 1) script.scrollTop = 0;
      lastTime = null;
      remainder = 0;
      frame = requestAnimationFrame(advance);
      update();
    });
    previous.addEventListener('click', () => selectCue(current - 1));
    next.addEventListener('click', () => selectCue(current + 1));
    freestyleButton.addEventListener('click', () => {
      pause();
      freestyle = !freestyle;
      update();
    });
    textSize.addEventListener('input', () => {
      pause();
      script.style.setProperty('--ll-teleprompter-size', `${textSize.value}px`);
    });
    script.addEventListener('wheel', pause, { passive: true });
    script.addEventListener('pointerdown', pause);
    script.addEventListener('keydown', event => {
      if (['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '].includes(event.key)) pause();
    });
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
