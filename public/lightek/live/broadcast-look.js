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

  function drawFrame(ctx, settings) {
    if (settings.frame === 'off') return;
    const sports = settings.frame === 'sports';
    ctx.save();
    ctx.globalAlpha = 1;
    ctx.filter = 'none';
    ctx.globalCompositeOperation = 'source-over';
    ctx.fillStyle = settings.frameColor;
    ctx.fillRect(0, 0, width, 34);
    ctx.fillRect(0, height - 39, width, 39);
    ctx.fillRect(0, 34, 10, height - 73);
    ctx.fillRect(width - 10, 34, 10, height - 73);

    ctx.fillStyle = settings.accent;
    ctx.fillRect(10, 32, width - 20, 2);
    ctx.fillRect(10, height - 40, width - 20, 2);
    for (const x of [0, width - 10]) {
      ctx.fillRect(x, 34, 10, 28);
      ctx.fillRect(x, height - 67, 10, 28);
    }
    const badgeWidth = sports ? 144 : 96;
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.lineTo(badgeWidth + (sports ? 20 : 0), 0);
    ctx.lineTo(badgeWidth, 32);
    ctx.lineTo(0, 32);
    ctx.fill();

    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.font = 'bold 14px system-ui';
    ctx.fillStyle = settings.accentInk;
    ctx.fillText(settings.badge || (sports ? 'SPORTS DESK' : 'NEWS'), 18, 16, badgeWidth - 36);
    ctx.fillStyle = settings.frameInk;
    ctx.font = 'bold 17px system-ui';
    ctx.fillText(settings.brand, badgeWidth + 30, 16, width - badgeWidth - 56);
    ctx.font = '600 20px system-ui';
    ctx.fillText(settings.headline, 28, height - 19, width - 56);
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

  function bindThemes(panel, field, kind, names) {
    const controls = panel.querySelector('[data-look-themes="' + kind + '"]');
    if (!controls) return;
    const get = selector => controls.querySelector(selector);
    const name = get('[data-theme-name]');
    const list = get('[data-theme-list]');
    const status = get('[data-theme-status]');
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
    get('[data-theme-load]').addEventListener('click', () => {
      const selected = themes.find(theme => theme.name === list.value);
      if (!selected) return void (status.textContent = 'Choose a saved theme.');
      for (const name of names) {
        const control = field(name);
        const value = selected.values[name];
        if (control.type === 'checkbox') {
          control.checked = value === true;
        } else if (typeof value === 'string' && (control.tagName !== 'SELECT' || Array.from(control.options).some(option => option.value === value))) {
          control.value = value;
        }
      }
      name.value = selected.name;
      status.textContent = 'Theme loaded into the controls. Apply it to the program when ready.';
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
    let settings, revision = 0;
    bindThemes(panel, field, 'frame', ['frame', 'brand', 'headline', 'badge', 'frame-color', 'accent']);
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

    panel.querySelector('[data-apply-broadcast-look]').addEventListener('click', async () => {
      const pending = ++revision;
      const next = {
        frame: field('frame').value,
        brand: field('brand').value.trim().slice(0, 40) || 'Lightek MCG',
        headline: field('headline').value.trim().slice(0, 90),
        badge: field('badge').value.trim().slice(0, 16),
        frameColor: field('frame-color').value,
        accent: field('accent').value,
        backdrop: field('backdrop').value,
        color: field('backdrop-color').value,
        baseColor: field('base-color').value,
        speed: Number(field('speed').value) || 2300,
        key: field('key').value,
        strength: Number(field('strength').value),
        motion: field('motion').checked
      };
      if (!isColor(next.accent)) next.accent = '#b5f58b';
      next.accentInk = accentInk(next.accent);
      if (!isColor(next.frameColor)) next.frameColor = '#0b1324';
      next.frameInk = accentInk(next.frameColor);
      if (!isColor(next.baseColor)) next.baseColor = '#091020';
      if (!isColor(next.color)) next.color = '#223d74';
      try {
        if (next.backdrop !== 'off' && !keyContext) throw Error('This browser could not start the green-screen compositor.');
        if (next.backdrop === 'image') {
          status.textContent = 'Loading backdrop image…';
          next.image = await loadImage(field('image').files[0]);
        }
        if (pending !== revision) return;
        settings = next;
        status.textContent = next.backdrop === 'off' ? 'Frame settings applied.' : 'Applied. The backdrop appears in Camera only.';
      } catch (error) {
        if (pending === revision) status.textContent = error.message;
      }
    });

    function clear() {
      revision++;
      settings = null;
      field('frame').value = field('backdrop').value = 'off';
      field('image').value = '';
      status.textContent = 'Frame and backdrop cleared.';
    }
    panel.querySelector('[data-clear-broadcast-look]').addEventListener('click', clear);

    return {
      drawFrame: ctx => { if (settings) drawFrame(ctx, settings); },
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
