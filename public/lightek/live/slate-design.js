(() => {
  const fonts = { sans: 'system-ui, sans-serif', serif: 'Georgia, serif', mono: 'monospace' };

  function fitImage(ctx, image, x, y, width, height, fill = false) {
    const scale = (fill ? Math.max : Math.min)(width / image.naturalWidth, height / image.naturalHeight);
    const w = image.naturalWidth * scale;
    const h = image.naturalHeight * scale;
    ctx.drawImage(image, x + (width - w) / 2, y + (height - h) / 2, w, h);
  }

  function lines(ctx, text, limit) {
    const rows = [];
    let row = '';
    for (const word of text.split(/\s+/)) {
      const next = row ? row + ' ' + word : word;
      if (row && ctx.measureText(next).width > limit) {
        rows.push(row);
        row = word;
      } else row = next;
    }
    if (row) rows.push(row);
    return rows.length > 2 ? [rows[0], rows[1] + '…'] : rows;
  }

  function draw(ctx, design) {
    const { settings, logo, background } = design;
    ctx.save();
    ctx.fillStyle = settings.base;
    ctx.fillRect(0, 0, 1280, 720);
    if (background) fitImage(ctx, background, 0, 0, 1280, 720, settings.fit === 'cover');
    if (settings.layout === 'artwork' && background) {
      ctx.restore();
      return;
    }
    if (background && Number(settings.shade)) {
      ctx.fillStyle = 'rgba(0,0,0,' + Number(settings.shade) / 100 + ')';
      ctx.fillRect(0, 0, 1280, 720);
    }
    const center = settings.layout === 'centered';
    const x = center ? 640 : 92;
    const font = fonts[settings.font] || fonts.sans;
    ctx.textAlign = center ? 'center' : 'left';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = settings.accent;
    ctx.fillRect(center ? 606 : 92, 270, 68, 5);
    ctx.fillRect(92, 635, 1096, 2);
    if (logo) {
      // Scale the logo to fit without distorting the source artwork.
      const width = Math.min(240, logo.naturalWidth / logo.naturalHeight * 102);
      fitImage(ctx, logo, center ? x - width / 2 : x, 75, width, 102);
    }
    ctx.fillStyle = settings.text;
    ctx.font = '600 23px ' + font;
    ctx.fillText(settings.brand, x, 221, 1096);
    ctx.font = 'bold 72px ' + font;
    const heading = lines(ctx, settings.heading, 1096);
    heading.forEach((line, index) => ctx.fillText(line, x, 359 + index * 78, 1096));
    ctx.font = '400 30px ' + font;
    lines(ctx, settings.message, 1096).forEach((line, index) =>
      ctx.fillText(line, x, 368 + heading.length * 78 + index * 38, 1096));
    ctx.font = '600 22px ' + font;
    ctx.fillText(settings.footer, x, 676, 1096);
    ctx.restore();
  }

  function boot(panel, legacyCopy) {
    const editor = panel.querySelector('[data-slate-design]');
    if (!editor) return null;
    const status = editor.querySelector('[data-slate-status]');
    const preview = editor.querySelector('[data-slate-preview]').getContext('2d');
    const fields = Array.from(editor.querySelectorAll('[data-slate-field]'));
    const read = () => Object.fromEntries(fields.map(field => [
      field.dataset.slateField, field.value.trim().slice(0, field.maxLength > 0 ? field.maxLength : 120)
    ]));
    const key = 'lightek:slate-design:v1:' + panel.dataset.breakScope;
    const images = new Map();
    let revision = 0;
    let settings = legacyCopy;
    try {
      settings = JSON.parse(localStorage.getItem(key) || 'null') || legacyCopy;
    } catch {
      status.textContent = 'The browser could not read saved slate settings.';
    }
    for (const field of fields) {
      const value = settings[field.dataset.slateField];
      if (typeof value === 'string' && (field.tagName !== 'SELECT' || Array.from(field.options).some(option => option.value === value))) {
        field.value = value;
      }
    }
    let applied = { settings: read() };

    function image(id) {
      if (!/^\d+$/.test(id)) return Promise.resolve(null);
      if (images.has(id)) return images.get(id);
      const promise = new Promise((resolve, reject) => {
        const node = new Image();
        const timeout = setTimeout(() => {
          node.src = '';
          reject(Error('Artwork took too long to load.'));
        }, 12000);
        node.onload = () => { clearTimeout(timeout); resolve(node); };
        node.onerror = () => { clearTimeout(timeout); reject(Error('Artwork could not load. Choose another Studio image.')); };
        node.src = '/api/lightek/pwa/assets/' + id + '/proxy';
      });
      images.set(id, promise);
      promise.catch(() => images.delete(id));
      return promise;
    }

    async function update(apply, initializing = false) {
      const current = ++revision;
      const settings = read();
      if (preview) draw(preview, { settings });
      if (apply && !initializing && settings.layout === 'artwork' && !settings.background) {
        status.textContent = 'Choose background artwork for Artwork only.';
        return;
      }
      try {
        const [logo, background] = await Promise.all([image(settings.logo), image(settings.background)]);
        if (current !== revision) return;
        const design = { settings, logo, background };
        if (preview) draw(preview, design);
        if (!apply) return;
        applied = design;
        if (initializing) return;
        try {
          localStorage.setItem(key, JSON.stringify(settings));
          status.textContent = 'Slate applied and saved.';
        } catch {
          status.textContent = 'Slate applied. Browser storage is unavailable.';
        }
      } catch (error) {
        if (current === revision) status.textContent = error.message;
      }
    }

    editor.addEventListener('input', () => update(false));
    editor.querySelector('[data-slate-apply]').addEventListener('click', () => update(true));
    update(true, true);
    return { draw: ctx => draw(ctx, applied) };
  }

  window.LightekSlateDesign = { boot };
})();
