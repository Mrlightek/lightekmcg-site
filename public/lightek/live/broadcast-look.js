/* Program canvas layers. The green-screen work canvas stays separate from capture. */
(() => {
  const width = 1280, height = 720;
  const isColor = value => /^#[0-9a-f]{6}$/i.test(value);

  function accentInk(color) {
    const channels = color.slice(1).match(/../g).map(byte => {
      const channel = parseInt(byte, 16) / 255;
      return channel <= .04045 ? channel / 12.92 : ((channel + .055) / 1.055) ** 2.4;
    });
    const luminance = channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
    return luminance > .179 ? '#000' : '#fff';
  }

  const widthSafe = 48;
  const heightSafe = 36;
  const frameStyles = {
    studio: { badge: 'LIVE', tint: '#42311f', accent: '#e3b76c', base: '#171720', texture: 'brushed', rail: 2, layout: 'signature' },
    news: { badge: 'NEWS DESK', tint: '#294c7b', accent: '#b3d8ff', base: '#101e31', texture: 'scanlines', rail: 2, layout: 'desk' },
    breaking: { badge: 'BREAKING', tint: '#8e2735', accent: '#f47877', base: '#2c1823', texture: 'scanlines', rail: 3, layout: 'alert' },
    sports: { badge: 'SPORTS DESK', tint: '#244c48', accent: '#c7f178', base: '#132521', texture: 'mesh', rail: 3, layout: 'score' },
    local: { badge: 'LOCAL REPORT', tint: '#21605f', accent: '#a8f0d5', base: '#10272c', texture: 'none', rail: 2, layout: 'desk' },
    cinema: { badge: 'LIGHTEK ORIGINAL', tint: '#513146', accent: '#edc797', base: '#201921', texture: 'brushed', rail: 2, layout: 'title' },
    entertainment: { badge: 'ON STAGE', tint: '#5b2b69', accent: '#ffc0ea', base: '#25182c', texture: 'none', rail: 3, layout: 'title' },
    gaming: { badge: 'GAMECAST', tint: '#2d3d74', accent: '#b8acf7', base: '#181d38', texture: 'mesh', rail: 3, layout: 'score' },
    affiliate: { badge: 'NETWORK FEED', tint: '#3b4b61', accent: '#d1e0f1', base: '#172330', texture: 'none', rail: 2, layout: 'signature' },
    sponsor: { badge: 'PRESENTED BY', tint: '#654624', accent: '#ffdb9b', base: '#251d15', texture: 'brushed', rail: 2, layout: 'credit' }
  };

  const frameFields = ['frame', 'brand', 'badge', 'frame-color', 'accent', 'texture', 'markers'];
  const validFrame = id => Object.hasOwn(frameStyles, id);

  function fitText(ctx, text, widthLimit) {
    if (ctx.measureText(text).width <= widthLimit) return text;
    const characters = Array.from(text);
    while (characters.length && ctx.measureText(characters.join('') + '…').width > widthLimit) characters.pop();
    return characters.join('').trimEnd() + '…';
  }

  function panelTint(color) {
    return '#' + color.slice(1).match(/../g).map(part =>
      Math.round(24 + parseInt(part, 16) * .28).toString(16).padStart(2, '0')
    ).join('');
  }

  function textureTile(kind) {
    if (kind === 'none') return null;
    const tile = document.createElement('canvas');
    tile.width = tile.height = 64;
    const ctx = tile.getContext('2d');
    if (kind === 'brushed') {
      for (let y = 0; y < 64; y += 2) {
        const x = (y * 29) % 64;
        ctx.fillStyle = y % 6 === 0 ? '#ffffff18' : '#00000036';
        ctx.fillRect(x, y, 64 - x, 1);
        ctx.fillRect(0, y, x / 2, 1);
      }
    } else if (kind === 'scanlines') {
      ctx.fillStyle = '#ffffff13';
      for (let y = 0; y < 64; y += 4) ctx.fillRect(0, y, 64, 1);
    } else if (kind === 'mesh') {
      ctx.fillStyle = '#d7f8ed2f';
      for (let y = 0; y < 64; y += 8) {
        for (let x = y % 16 ? 4 : 0; x < 64; x += 8) ctx.fillRect(x, y, 2, 2);
      }
    }
    return tile;
  }

  function panel(ctx, x, y, w, h, style, settings, clipped) {
    const background = ctx.createLinearGradient(x, y, x + w, y + h);
    background.addColorStop(0, style.base);
    background.addColorStop(.64, style.base);
    background.addColorStop(1, panelTint(settings.frameColor));
    ctx.fillStyle = background;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + w - clipped, y);
    ctx.lineTo(x + w, y + clipped);
    ctx.lineTo(x + w, y + h);
    ctx.lineTo(x, y + h);
    ctx.closePath();
    ctx.fill();
    if (settings.pattern) {
      ctx.fillStyle = settings.pattern;
      ctx.fill();
    }
  }

  function drawFrame(ctx, settings) {
    if (!validFrame(settings.frame)) return;
    const style = frameStyles[settings.frame];
    const { accent } = settings;
    const left = widthSafe;
    const top = heightSafe + 12;
    const score = style.layout === 'score';
    const alert = style.layout === 'alert';
    const title = style.layout === 'title';
    const credit = style.layout === 'credit';
    const right = style.layout === 'signature' || credit;
    const bevel = score || title ? 14 : 0;
    ctx.save();

    if (settings.markers) {
      ctx.strokeStyle = accent;
      ctx.globalAlpha = .65;
      ctx.lineWidth = style.rail;
      ctx.beginPath();
      const inset = 32;
      for (const [x, y, dx, dy] of [
        [inset, inset, 1, 1], [width - inset, inset, -1, 1],
        [inset, height - inset, 1, -1], [width - inset, height - inset, -1, -1]
      ]) {
        ctx.moveTo(x, y + dy * 19);
        ctx.lineTo(x, y);
        ctx.lineTo(x + dx * (score ? 54 : 32), y);
      }
      ctx.stroke();
      ctx.globalAlpha = 1;
    }

    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.font = '750 16px system-ui';
    const label = fitText(ctx, settings.badge || style.badge, 180);
    const badgeWidth = Math.ceil(ctx.measureText(label).width) + 24;
    ctx.font = '650 21px system-ui';
    const brand = fitText(ctx, settings.brand, 340);
    const brandOffset = badgeWidth + 24;
    const identityWidth = brandOffset + Math.ceil(ctx.measureText(brand).width) + 25;
    const x = right ? width - left - identityWidth : left;
    panel(ctx, x, top, identityWidth, 44, style, settings, bevel);
    ctx.fillStyle = accent;
    ctx.fillRect(x + 8, top + 8, badgeWidth, 28);
    ctx.font = '750 16px system-ui';
    ctx.fillStyle = settings.accentInk;
    ctx.fillText(label, x + 20, top + 22);
    ctx.fillStyle = '#f8f7f3';
    ctx.font = '650 21px system-ui';
    ctx.fillText(brand, x + brandOffset, top + 22);

    if (score && settings.score) {
      ctx.font = '700 23px ui-monospace, monospace';
      const game = fitText(ctx, settings.score, 384);
      const scoreWidth = Math.ceil(ctx.measureText(game).width) + 36;
      const scoreX = width - left - scoreWidth;
      panel(ctx, scoreX, top, scoreWidth, 44, style, settings, bevel);
      ctx.fillStyle = accent;
      ctx.fillRect(scoreX, top + 42, scoreWidth, 2);
      ctx.fillStyle = '#f8f7f3';
      ctx.fillText(game, scoreX + 17, top + 23);
    }

    if (settings.headline) {
      const headlineFont = title ? '600 32px Georgia, serif' : alert ? '750 29px system-ui' : '650 26px system-ui';
      ctx.font = headlineFont;
      const headline = fitText(ctx, settings.headline, 790);
      const headlineWidth = ctx.measureText(headline).width;
      ctx.font = '500 18px system-ui';
      const subtitle = fitText(ctx, settings.subtitle, 790);
      const subtitleWidth = ctx.measureText(subtitle).width;
      const h = subtitle ? 80 : alert || title ? 62 : 53;
      const y = height - heightSafe - 12 - h;
      const w = Math.max(alert ? 340 : 226, Math.ceil(Math.max(headlineWidth, subtitleWidth)) + 54);
      const headlineX = credit ? width - left - w : title ? Math.round((width - w) / 2) : left;
      panel(ctx, headlineX, y, w, h, style, settings, bevel);
      ctx.fillStyle = accent;
      ctx.fillRect(headlineX, y, style.rail, h);
      if (alert || title) ctx.fillRect(headlineX, y, w - bevel, 2);
      ctx.fillStyle = '#f8f7f3';
      ctx.font = headlineFont;
      ctx.textAlign = title ? 'center' : 'left';
      const copyX = headlineX + (title ? w / 2 : 24);
      ctx.fillText(headline, copyX, y + (subtitle ? 25 : h / 2));
      if (subtitle) {
        ctx.fillStyle = '#d3dce9';
        ctx.font = '500 18px system-ui';
        ctx.fillText(subtitle, copyX, y + 56);
      }
    }

    ctx.restore();
  }

  function drawBackdrop(ctx, settings, time) {
    ctx.fillStyle = settings.baseColor;
    ctx.fillRect(0, 0, width, height);
    if (settings.backdrop === 'image') {
      const image = settings.image;
      const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight);
      const w = image.naturalWidth * scale, h = image.naturalHeight * scale;
      ctx.drawImage(image, (width - w) / 2, (height - h) / 2, w, h);
      return;
    }

    const sports = settings.backdrop === 'sports';
    const phase = settings.motion ? Math.sin(time / settings.speed) : 0;
    const gradient = ctx.createRadialGradient(640 + phase * 240, 180, 25, 640 + phase * 240, 180, 890);
    gradient.addColorStop(0, settings.color);
    gradient.addColorStop(1, settings.baseColor);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
    if (settings.backdrop === 'minimal') return;
    ctx.save();
    ctx.strokeStyle = sports ? '#d3edff' : '#8daee8';
    ctx.globalAlpha = sports ? .22 : .17;
    ctx.lineWidth = sports ? 3 : 1;
    const offset = phase * 35;
    ctx.beginPath();
    for (let x = -260; x < width + 470; x += sports ? 118 : 82) {
      ctx.moveTo(x + offset, 0);
      ctx.lineTo(sports ? x + offset - 390 : 640 + (x - 640) * 1.5 + offset, height);
    }
    if (!sports) {
      for (const y of [96, 180, 277, 387, 510, 645]) {
        ctx.moveTo(0, y);
        ctx.lineTo(width, y);
      }
    }
    ctx.stroke();
    ctx.restore();
  }

  function keyPixels(pixels, key, strength) {
    const selected = key === 'blue' ? 2 : 1;
    const other = selected === 2 ? 1 : 2;
    const lower = strength * 1.9;
    const upper = lower + 32;
    for (let i = 0; i < pixels.length; i += 4) {
      const neutral = Math.max(pixels[i], pixels[i + other]);
      const dominance = pixels[i + selected] - neutral;
      if (dominance <= lower) continue;
      const t = Math.min(1, (dominance - lower) / (upper - lower));
      pixels[i + 3] *= 1 - t * t * (3 - 2 * t);
      pixels[i + selected] -= dominance * t;
    }
  }

  function bindThemes(panel, field, kind, names, onLoad) {
    const controls = panel.querySelector('[data-look-themes="' + kind + '"]');
    if (!controls) return;
    const get = selector => controls.querySelector(selector);
    const name = get('[data-theme-name]');
    const list = get('[data-theme-list]');
    const status = get('[data-theme-status]');
    const exportButton = get('[data-theme-export]');
    const importInput = get('[data-theme-import]');
    const key = 'lightek:broadcast-themes:v1:' + panel.dataset.themeScope + ':' + kind;
    let themes = [];
    function refresh(selected = '') {
      list.replaceChildren(new Option('Choose a saved theme', ''));
      for (const theme of themes) list.add(new Option(theme.name, theme.name));
      list.value = selected;
    }

    function store(next, selected, message) {
      try {
        localStorage.setItem(key, JSON.stringify(next));
        themes = next;
        refresh(selected);
        status.textContent = message;
      } catch {
        status.textContent = 'The browser could not save themes.';
      }
    }

    try {
      const saved = JSON.parse(localStorage.getItem(key) || '[]');
      if (Array.isArray(saved)) {
        themes = saved.filter(theme => typeof theme?.name === 'string' && theme.name && theme.values).slice(0, 24);
      }
    } catch {
      status.textContent = 'Saved themes are unavailable in this browser.';
    }
    refresh();
    get('[data-theme-save]').addEventListener('click', () => {
      const title = name.value.trim().slice(0, 40);
      if (!title) return void (status.textContent = 'Enter a name for the theme.');
      const style = field(kind === 'frame' ? 'frame' : 'backdrop').value;
      if (style === 'off' || style === 'image') {
        status.textContent = 'Choose a designed style to save as a theme.';
        return;
      }
      const existing = themes.find(theme => theme.name === title);
      if (themes.length >= 24 && !existing) return void (status.textContent = 'Delete a saved theme to make room for another.');
      const values = Object.fromEntries(names.map(name => {
        const control = field(name);
        return [name, control.type === 'checkbox' ? control.checked : control.value];
      }));
      const next = themes.filter(theme => theme !== existing).concat({ name: title, values });
      store(next, title, existing ? 'Theme updated.' : 'Theme saved.');
    });
    function loadDraft(selected) {
      for (const name of names) {
        const control = field(name);
        const value = selected.values[name] ?? (name === 'texture' ? 'auto' : name === 'markers' ? true : undefined);
        if (control.type === 'checkbox') {
          control.checked = value === true;
        } else if (typeof value === 'string' && (control.tagName !== 'SELECT' || Array.from(control.options).some(option => option.value === value))) {
          control.value = control.maxLength > 0 ? value.slice(0, control.maxLength) : value;
        }
      }
      onLoad?.();
      name.value = selected.name;
    }

    get('[data-theme-load]').addEventListener('click', () => {
      const selected = themes.find(theme => theme.name === list.value);
      if (!selected) return void (status.textContent = 'Choose a saved theme.');
      loadDraft(selected);
      status.textContent = 'Theme loaded into the controls. Apply it to the program when ready.';
    });

    exportButton?.addEventListener('click', () => {
      const selected = themes.find(theme => theme.name === list.value);
      if (!selected) return void (status.textContent = 'Choose a saved look to export.');
      const values = Object.fromEntries(frameFields.filter(key => Object.hasOwn(selected.values, key))
        .map(key => [key, selected.values[key]]));
      const blob = new Blob([JSON.stringify({ version: 1, name: selected.name, values }, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'lightek-broadcast-look.json';
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = 'Look exported.';
    });

    importInput?.addEventListener('change', async () => {
      const file = importInput.files[0];
      if (!file) return;
      importInput.value = '';
      try {
        if (file.size > 8192) throw Error();
        const { version, name: title, values } = JSON.parse(await file.text());
        if (version !== 1 || typeof title !== 'string' || !title.trim() || !values || !validFrame(values.frame)) throw Error();
        const { frame, brand, badge, accent, texture = 'auto', markers = true } = values;
        if (typeof brand !== 'string' || typeof badge !== 'string' || typeof markers !== 'boolean' ||
          !isColor(accent) || !isColor(values['frame-color']) ||
          !Array.from(field('texture').options).some(option => option.value === texture)) throw Error();
        list.value = '';
        for (const key of ['headline', 'subtitle', 'score']) field(key).value = '';
        loadDraft({ name: title.trim().slice(0, 40), values: { frame, brand, badge, accent, texture, markers, 'frame-color': values['frame-color'] } });
        status.textContent = 'Look imported into the private preview. Save it under a new name to keep it.';
      } catch {
        status.textContent = 'Choose a valid Lightek broadcast look file.';
      }
    });
    get('[data-theme-delete]').addEventListener('click', () => {
      if (!list.value) return void (status.textContent = 'Choose a saved theme.');
      store(themes.filter(theme => theme.name !== list.value), '', 'Theme deleted.');
    });
  }

  function boot(root) {
    const panel = root.querySelector('[data-broadcast-look]');
    if (!panel) return null;
    const field = name => panel.querySelector('[data-look="' + name + '"]');
    const status = panel.querySelector('[data-broadcast-look-status]');
    const work = document.createElement('canvas');
    const keyContext = work.getContext('2d', { willReadFrequently: true });
    const frameCanvas = document.createElement('canvas');
    frameCanvas.width = width;
    frameCanvas.height = height;
    const frameContext = frameCanvas.getContext('2d');
    let settings, revision = 0;
    const frameChoice = field('frame');
    const previewCanvas = panel.querySelector('[data-look-preview]');
    const previewContext = previewCanvas.getContext('2d');
    const showScoreControl = () => { panel.querySelector('[data-look-score]').hidden = frameStyles[frameChoice.value]?.layout !== 'score'; };
    showScoreControl();
    frameChoice.addEventListener('change', () => {
      const choice = frameStyles[frameChoice.value];
      if (choice) {
        field('frame-color').value = choice.tint;
        field('accent').value = choice.accent;
        field('texture').value = 'auto';
      }
      showScoreControl();
      updatePreview();
    });
    bindThemes(panel, field, 'frame', [...frameFields, 'headline', 'subtitle'], () => {
      showScoreControl();
      updatePreview();
    });
    panel.querySelector('[data-look-frame-controls]').addEventListener('input', updatePreview);
    updatePreview();
    bindThemes(panel, field, 'background', ['backdrop', 'base-color', 'backdrop-color', 'motion', 'speed']);

    function loadImage(file) {
      if (!file || file.size > 12 * 1024 * 1024 || !['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) {
        throw Error('Choose a PNG, JPEG or WebP image up to 12 MB.');
      }
      return new Promise((resolve, reject) => {
        const url = URL.createObjectURL(file);
        const image = new Image();
        image.onload = () => {
          URL.revokeObjectURL(url);
          if (image.naturalWidth > 4096 || image.naturalHeight > 4096) reject(Error('Use an image up to 4096 pixels per side.'));
          else resolve(image);
        };
        image.onerror = () => {
          URL.revokeObjectURL(url);
          reject(Error('The browser could not open this image.'));
        };
        image.src = url;
      });
    }

    function frameDraft() {
      const accent = field('accent').value;
      const frameColor = field('frame-color').value;
      return {
        frame: field('frame').value,
        brand: field('brand').value.trim().slice(0, 40) || 'Lightek MCG',
        headline: field('headline').value.trim().slice(0, 90),
        subtitle: field('subtitle').value.trim().slice(0, 80),
        badge: field('badge').value.trim().slice(0, 16),
        score: field('score').value.trim().slice(0, 40),
        frameColor: isColor(frameColor) ? frameColor : '#0b1324',
        accent: isColor(accent) ? accent : '#d6aa58',
        texture: field('texture').value,
        markers: field('markers').checked
      };
    }

    function renderLook(ctx, draft) {
      ctx.clearRect(0, 0, width, height);
      if (!validFrame(draft.frame)) return;
      const texture = draft.texture === 'auto' ? frameStyles[draft.frame].texture : draft.texture;
      const tile = textureTile(texture);
      drawFrame(ctx, { ...draft, pattern: tile && ctx.createPattern(tile, 'repeat'), accentInk: accentInk(draft.accent) });
    }

    function updatePreview() {
      const draft = frameDraft();
      if (draft.frame !== 'off' && !draft.headline) {
        draft.headline = 'Your headline goes here';
        draft.subtitle ||= 'Optional second line';
      }
      renderLook(previewContext, draft);
    }

    async function applyLook() {
      const pending = ++revision;
      const next = {
        ...frameDraft(),
        backdrop: field('backdrop').value,
        color: field('backdrop-color').value,
        baseColor: field('base-color').value,
        speed: Number(field('speed').value) || 2300,
        key: field('key').value,
        strength: Number(field('strength').value),
        motion: field('motion').checked
      };
      if (!isColor(next.baseColor)) next.baseColor = '#091020';
      if (!isColor(next.color)) next.color = '#223d74';
      try {
        if (next.backdrop !== 'off' && !keyContext) throw Error('This browser could not start the green-screen compositor.');
        if (next.backdrop === 'image') {
          status.textContent = 'Loading backdrop image…';
          next.image = await loadImage(field('image').files[0]);
        }
        if (pending !== revision) return;
        renderLook(frameContext, next);
        settings = next;
        status.textContent = next.backdrop === 'off' ? 'Frame settings applied.' : 'Applied. The backdrop appears in Camera only.';
      } catch (error) {
        if (pending === revision) status.textContent = error.message;
      }
    }
    panel.querySelector('[data-apply-broadcast-look]').addEventListener('click', applyLook);
    if (validFrame(panel.dataset.preparedFrame) || panel.dataset.preparedFrame === 'off') {
      frameChoice.value = panel.dataset.preparedFrame;
      frameChoice.dispatchEvent(new Event('change'));
      applyLook();
    }

    function clear() {
      revision++;
      settings = null;
      field('frame').value = field('backdrop').value = 'off';
      field('image').value = '';
      showScoreControl();
      updatePreview();
      status.textContent = 'Frame and backdrop cleared.';
    }
    panel.querySelector('[data-clear-broadcast-look]').addEventListener('click', clear);

    return {
      drawFrame: ctx => {
        if (!validFrame(settings?.frame)) return;
        ctx.save();
        ctx.globalAlpha = 1;
        ctx.filter = 'none';
        ctx.globalCompositeOperation = 'source-over';
        ctx.drawImage(frameCanvas, 0, 0);
        ctx.restore();
      },
      drawKeyedCamera(ctx, camera, rect, time) {
        if (!settings || settings.backdrop === 'off') return false;
        const scale = Math.min(1, 640 / camera.videoWidth, 360 / camera.videoHeight);
        const w = Math.max(1, Math.round(camera.videoWidth * scale));
        const h = Math.max(1, Math.round(camera.videoHeight * scale));
        if (work.width !== w) work.width = w;
        if (work.height !== h) work.height = h;
        if (settings.keyFailed) {
          drawBackdrop(ctx, settings, time);
          return true;
        }
        try {
          keyContext.drawImage(camera, 0, 0, w, h);
          const frame = keyContext.getImageData(0, 0, w, h);
          keyPixels(frame.data, settings.key, settings.strength);
          keyContext.putImageData(frame, 0, 0);
          drawBackdrop(ctx, settings, time);
          ctx.drawImage(work, ...rect);
          return true;
        } catch {
          settings.keyFailed = true;
          status.textContent = 'Green screen stopped. The backdrop is shown without the camera. Reapply to retry.';
          drawBackdrop(ctx, settings, time);
          return true;
        }
      }
    };
  }

  window.LightekBroadcastLook = { boot };
})();
