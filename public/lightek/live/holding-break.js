(() => {
  function drawSlate(ctx, { brand, heading, message }) {
    ctx.fillStyle = '#0b121b';
    ctx.fillRect(0, 0, 1280, 720);
    ctx.fillStyle = '#b5f58b';
    ctx.font = '600 22px system-ui';
    ctx.fillText(brand, 90, 110, 1100);
    ctx.fillStyle = '#f2f5fa';
    ctx.font = 'bold 56px system-ui';
    ctx.fillText(heading, 90, 340, 1100);
    ctx.fillStyle = '#a7b4c6';
    ctx.font = '24px system-ui';
    ctx.fillText(message, 90, 390, 1100);
  }

  function boot(root) {
    const panel = root.querySelector('[data-holding-break]');
    if (!panel) return null;
    const q = selector => panel.querySelector(selector);
    const brand = q('[data-break-brand-input]');
    const heading = q('[data-break-heading]');
    const message = q('[data-break-message]');
    const items = Array.from(panel.querySelectorAll('[data-break-item]'));
    const musicChoice = q('[data-break-music]');
    const volume = q('[data-break-volume]');
    const nextButton = q('[data-break-next]');
    const status = q('[data-break-status]');
    const key = 'lightek:holding-break:v1:' + panel.dataset.breakScope;
    let active = false, queue = [], index = 0, visual, music, timer, audio, mixer;
    let breakId = 0, itemId = 0;

    function slate() {
      return {
        brand: brand.value.trim().slice(0, 60) || panel.dataset.breakBrand,
        heading: heading.value.trim().slice(0, 70) || 'Back in a moment.',
        message: message.value.trim().slice(0, 120)
      };
    }

    try {
      const saved = JSON.parse(localStorage.getItem(key) || 'null');
      if (saved) {
        for (const [field, value] of [[brand, saved.brand], [heading, saved.heading], [message, saved.message], [volume, saved.volume]]) {
          if (typeof value === 'string') field.value = value;
        }
        for (const [field, value] of [[musicChoice, saved.music], ...items.map((item, i) => [item, saved.items?.[i]])]) {
          if (Array.from(field.options).some(option => option.value === value)) field.value = value;
        }
      }
    } catch {
      status.textContent = 'Saved break settings are unavailable in this browser.';
    }
    q('[data-break-save]').addEventListener('click', () => {
      try {
        localStorage.setItem(key, JSON.stringify({
          ...slate(), volume: volume.value, music: musicChoice.value, items: items.map(item => item.value)
        }));
        status.textContent = 'Break settings saved to this browser.';
      } catch {
        status.textContent = 'The browser could not save break settings.';
      }
    });

    function media(id, kind) {
      const element = document.createElement(kind === 'image' ? 'img' : kind);
      const entry = { element, kind };
      if (kind !== 'image') {
        element.playsInline = true;
        element.preload = 'auto';
        element.crossOrigin = 'use-credentials';
        entry.source = audio.createMediaElementSource(element);
        entry.gain = audio.createGain();
        entry.gain.gain.value = 0;
        entry.source.connect(entry.gain).connect(mixer);
      }
      entry.url = '/api/lightek/pwa/assets/' + id + '/proxy';
      return entry;
    }

    function dispose(entry) {
      if (!entry) return;
      if (entry.gain) entry.gain.gain.value = 0;
      entry.element.pause?.();
      entry.element.removeAttribute('src');
      entry.element.load?.();
      entry.source?.disconnect();
      entry.gain?.disconnect();
    }

    function mixMusic() {
      if (music?.gain) music.gain.gain.value = active && visual?.kind !== 'video' ? Number(volume.value) : 0;
    }
    volume.addEventListener('input', mixMusic);

    function advance() {
      clearTimeout(timer);
      const current = ++itemId;
      dispose(visual);
      visual = null;
      if (!active) return;
      const item = queue[index++];
      nextButton.disabled = !item;
      if (!item) {
        mixMusic();
        status.textContent = 'Holding slate is on program.';
        return;
      }

      const skip = () => { if (active && itemId === current) advance(); };
      try {
        const entry = visual = media(item.id, item.kind);
        status.textContent = 'Loading break item ' + index + ' of ' + queue.length + '…';
        const ready = () => {
          if (!active || itemId !== current) return;
          clearTimeout(timer);
          entry.ready = true;
          status.textContent = 'Break item ' + index + ' of ' + queue.length + ' is on program.';
          if (item.kind === 'image') timer = setTimeout(skip, 10000);
          else {
            entry.gain.gain.value = 1;
            entry.element.play().catch(skip);
          }
        };
        entry.element.addEventListener(item.kind === 'image' ? 'load' : 'canplay', ready, { once: true });
        entry.element.addEventListener('error', skip, { once: true });
        entry.element.addEventListener('ended', skip, { once: true });
        mixMusic();
        timer = setTimeout(skip, 12000);
        entry.element.src = entry.url;
      } catch {
        skip();
      }
    }
    nextButton.addEventListener('click', advance);

    function stop() {
      if (active) status.textContent = 'Break stopped.';
      active = false;
      breakId++;
      advance();
      dispose(music);
      music = null;
      nextButton.disabled = true;
    }

    return {
      start(context, output) {
        stop();
        active = true;
        const current = breakId;
        audio = context;
        mixer = output;
        queue = items.flatMap(select => {
          const option = select.selectedOptions[0];
          return /^\d+$/.test(option?.value) && ['image', 'video'].includes(option.dataset.kind)
            ? [{ id: option.value, kind: option.dataset.kind }]
            : [];
        });
        index = 0;
        const id = musicChoice.value;
        if (/^\d+$/.test(id)) {
          try {
            const entry = music = media(id, 'audio');
            entry.element.loop = true;
            const disable = () => {
              if (current !== breakId || music !== entry) return;
              music = null;
              dispose(entry);
            };
            entry.element.addEventListener('error', disable, { once: true });
            entry.element.src = entry.url;
            entry.element.play().catch(disable);
          } catch {
            dispose(music);
            music = null;
          }
        }
        advance();
      },
      stop,
      draw(ctx) {
        drawSlate(ctx, slate());
        if (!active || !visual?.ready) return;
        const { element } = visual;
        const w = element.videoWidth || element.naturalWidth;
        const h = element.videoHeight || element.naturalHeight;
        if (!(w && h)) return;
        const scale = Math.min(1280 / w, 720 / h);
        ctx.fillStyle = '#0b121b';
        ctx.fillRect(0, 0, 1280, 720);
        ctx.drawImage(element, (1280 - w * scale) / 2, (720 - h * scale) / 2, w * scale, h * scale);
      }
    };
  }

  window.LightekHoldingBreak = { boot };
})();
