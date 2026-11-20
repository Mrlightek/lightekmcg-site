(() => {
  const width = 1280, height = 720;

  function boot(root) {
    const panel = root.querySelector('[data-live-effects]');
    const motion = window.LightekLiveMotion;
    if (!panel || !motion) return null;
    const field = name => panel.querySelector('[data-effect="' + name + '"]');
    const note = panel.querySelector('[data-effects-status]');
    const preview = panel.querySelector('[data-effects-preview]').getContext('2d');
    const layer = document.createElement('canvas');
    layer.width = width;
    layer.height = height;
    const layerContext = layer.getContext('2d');
    const gifCanvas = document.createElement('canvas');
    const gifContext = gifCanvas.getContext('2d');
    const exportButton = panel.querySelector('[data-effects-export]');
    const download = panel.querySelector('[data-effects-download]');
    const scrub = panel.querySelector('[data-effects-scrub]');
    const logoInput = field('logo');
    const removeLogo = panel.querySelector('[data-effects-remove-logo]');
    const library = panel.querySelector('[data-effects-library]');
    const libraryKey = 'lightek:live-motion:v1:' + panel.dataset.effectsScope;
    const saved = library.querySelector('[data-effects-saved]');
    const graphicName = library.querySelector('[data-effects-name]');
    const loadGraphic = library.querySelector('[data-effects-load]');
    const deleteGraphic = library.querySelector('[data-effects-delete]');
    const graphicFields = ['kind', 'title', 'subtitle', 'color', 'accent', 'x', 'y', 'size',
      'opacity', 'seconds', 'entrance', 'exit', 'stagger', 'easing'];
    let program, draft, animationRequest, gif, worker, revision = 0, workerTimer, displayedFrame;
    let exportWorker, exportTimer, downloadUrl;
    let logo, logoData, designRevision = 0;

    function render(ctx, cue, now) {
      const elapsed = Math.max(0, now - cue.start);
      if (!cue.loop && elapsed >= cue.duration) return false;
      const time = elapsed % cue.duration;
      ctx.save();
      ctx.translate(cue.x, cue.y);
      ctx.globalAlpha = cue.opacity;
      if (cue.gif) {
        const frame = cue.gif.frames.find(frame => frame.end > time / cue.duration * cue.gif.duration);
        if (displayedFrame !== frame && frame) {
          if (gifCanvas.width !== cue.gif.width) gifCanvas.width = cue.gif.width;
          if (gifCanvas.height !== cue.gif.height) gifCanvas.height = cue.gif.height;
          gifContext.putImageData(frame.image, 0, 0);
          displayedFrame = frame;
        }
        const scale = cue.size / Math.max(cue.gif.width, cue.gif.height);
        const w = cue.gif.width * scale, h = cue.gif.height * scale;
        ctx.drawImage(gifCanvas, -w / 2, -h / 2, w, h);
      } else {
        const progress = time / cue.duration;
        motion.draw(ctx, cue, progress);
      }
      ctx.restore();
      return true;
    }

    function cue() {
      const kind = field('kind').value;
      if (kind === 'gif' && !gif) throw Error('Load a GIF before adding it to the layer.');
      const number = (name, min, max, fallback) => {
        const input = field(name);
        const value = Number(input.value);
        return input.value && Number.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
      };
      const pct = (name, fallback) => number(name, 0, 100, fallback) / 100;
      const easing = field('easing').value;
      const effect = {
        kind,
        color: field('color').value,
        accent: field('accent').value,
        title: field('title').value.trim().slice(0, 44) || 'Lightek Live',
        subtitle: field('subtitle').value.trim().slice(0, 64),
        x: pct('x', 0) * width,
        y: pct('y', 0) * height,
        size: pct('size', 35) * width,
        opacity: pct('opacity', 85),
        gif: kind === 'gif' ? gif : null,
        logo: motion.textKinds.has(kind) ? logo : null,
        loop: field('loop').checked,
        duration: number('seconds', 1, 30, 3) * 1000,
        entrance: number('entrance', 0, 4, .55),
        exit: number('exit', 0, 4, .5),
        stagger: motion.textKinds.has(kind) ? number('stagger', 0, 1, .07) : 0,
        easing: motion.eases.has(easing) ? easing : 'power2.out',
        start: performance.now()
      };
      if (!effect.gif) effect.animation = motion.animate(effect);
      return effect;
    }

    function cancelDecode() {
      clearTimeout(workerTimer);
      worker?.terminate();
      worker = null;
    }
    field('file').addEventListener('change', async () => {
      const current = ++revision;
      cancelDecode();
      gif = null;
      const file = field('file').files[0];
      if (!file) return;
      if (field('kind').value !== 'gif') {
        field('kind').value = 'gif';
        designRevision++;
        selectPreset();
      }
      if (file.size > 3 * 1024 * 1024) {
        note.textContent = 'Choose a GIF smaller than 3 MB.';
        return;
      }
      try {
        note.textContent = 'Reading GIF…';
        const data = await file.arrayBuffer();
        if (revision !== current) return;
        const decoder = worker = new Worker('/lightek/live/effects-gif-worker.js?v=1');
        const failed = message => {
          if (worker !== decoder) return;
          cancelDecode();
          note.textContent = message;
        };
        workerTimer = setTimeout(() => failed('GIF decoding timed out.'), 10000);
        decoder.onerror = () => failed('GIF decoding is unavailable.');
        decoder.onmessage = ({data}) => {
          if (worker !== decoder) return;
          if (data.error) return failed(data.error);
          cancelDecode();
          const { frames, width, height, duration } = data;
          gif = { width, height, duration, frames: frames.map(frame => ({
            end: frame.end, image: new ImageData(new Uint8ClampedArray(frame.pixels), width, height)
          })) };
          if (field('kind').value === 'gif') {
            field('seconds').value = Math.max(1, Math.min(30, Math.round(duration / 1000)));
            showPoster();
          }
          note.textContent = 'GIF loaded. Preview it or cue it on program.';
        };
        decoder.postMessage(data, [data]);
      } catch {
        if (revision === current) note.textContent = 'The GIF file could not be opened.';
      }
    });

    function showPoster() {
      cancelAnimationFrame(animationRequest);
      draft = null;
      preview.clearRect(0, 0, width, height);
      if (field('kind').value === 'gif' && !gif) return;
      const sample = cue();
      // A one-shot preview expires at the end, so sample the final instant just before it.
      const position = Math.min(.999999, Number(scrub.value) / 100);
      render(preview, sample, sample.start + sample.duration * position);
    }

    function selectPreset() {
      const kind = field('kind').value;
      const [x, y, size, opacity] = ({
        nameplate: [25, 80, 38, 100], opener: [50, 48, 58, 100],
        sweep: [50, 52, 64, 90], traces: [50, 45, 40, 90],
        rings: [50, 45, 35, 85], confetti: [50, 38, 62, 90], gif: [50, 45, 35, 85]
      })[kind];
      Object.entries({x, y, size, opacity}).forEach(([key, value]) => { field(key).value = value; });
      panel.querySelector('[data-effect-text-controls]').hidden = !motion.textKinds.has(kind);
      panel.querySelector('[data-effect-gif-controls]').hidden = kind !== 'gif';
      panel.querySelector('[data-effect-palette]').hidden = kind === 'gif';
      panel.querySelector('[data-effect-export-note]').hidden = kind === 'gif';
      panel.querySelector('[data-effect-animation]').hidden = kind === 'gif';
      panel.querySelector('[data-effect-stagger]').hidden = !motion.textKinds.has(kind);
      panel.querySelector('[data-effects-scrub-controls]').hidden = kind === 'gif';
      exportButton.hidden = kind === 'gif';
      library.querySelector('[data-effects-save]').disabled = kind === 'gif';
      showPoster();
    }
    field('kind').addEventListener('change', () => {
      designRevision++;
      selectPreset();
    });
    scrub.addEventListener('input', showPoster);
    panel.addEventListener('input', event => {
      if (event.target.matches('input[data-effect]:not([type="file"]), [data-effect="easing"]')) showPoster();
    });
    selectPreset();

    function readImage(url) {
      return new Promise((resolve, reject) => {
        const image = new Image();
        image.onload = () => resolve(image);
        image.onerror = reject;
        image.src = url;
      });
    }

    function setLogo(image, data) {
      logo = image;
      logoData = data;
      logoInput.value = '';
      removeLogo.hidden = !logo;
      showPoster();
    }

    logoInput.addEventListener('change', async () => {
      const file = logoInput.files[0];
      if (!file) return;
      const current = ++designRevision;
      if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type) || file.size > 3 * 1024 * 1024) {
        note.textContent = 'Choose a PNG, JPEG, or WebP logo up to 3 MB.';
        logoInput.value = '';
        return;
      }
      const url = URL.createObjectURL(file);
      try {
        const image = await readImage(url);
        if (current !== designRevision) return;
        const canvas = document.createElement('canvas');
        const scale = Math.min(1, 256 / Math.max(image.width, image.height));
        canvas.width = Math.max(1, Math.round(image.width * scale));
        canvas.height = Math.max(1, Math.round(image.height * scale));
        canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
        setLogo(canvas, canvas.toDataURL('image/png'));
        note.textContent = 'Logo added to the graphic.';
      } catch {
        if (current === designRevision) note.textContent = 'The logo could not be opened.';
      } finally {
        URL.revokeObjectURL(url);
      }
    });

    removeLogo.addEventListener('click', () => {
      designRevision++;
      setLogo(null, null);
      note.textContent = 'Logo removed.';
    });

    function savedGraphics() {
      const entries = JSON.parse(localStorage.getItem(libraryKey) || '[]');
      return Array.isArray(entries) ? entries : [];
    }

    function updateLibrary(entries, name = '') {
      saved.replaceChildren(new Option('Choose a graphic', ''));
      entries.forEach(item => saved.add(new Option(item.name, item.name)));
      saved.value = name;
      loadGraphic.disabled = !saved.value;
      deleteGraphic.hidden = !saved.value;
    }

    try { updateLibrary(savedGraphics()); }
    catch { updateLibrary([]); }
    saved.addEventListener('change', () => {
      designRevision++;
      loadGraphic.disabled = !saved.value;
      deleteGraphic.hidden = !saved.value;
    });
    loadGraphic.addEventListener('click', async () => {
      const current = ++designRevision;
      try {
        const graphic = savedGraphics().find(item => item.name === saved.value);
        if (!graphic || !Array.from(field('kind').options).some(option =>
          option.value !== 'gif' && option.value === graphic.fields.kind)) return;
        const data = /^data:image\/png;base64,[a-z0-9+/=]+$/i.test(graphic.logo) ? graphic.logo : null;
        const image = data ? await readImage(data) : null;
        if (current !== designRevision) return;
        field('kind').value = graphic.fields.kind;
        selectPreset();
        graphicFields.forEach(key => {
          if (typeof graphic.fields[key] === 'string') field(key).value = graphic.fields[key];
        });
        field('loop').checked = graphic.loop === true;
        graphicName.value = graphic.name;
        setLogo(image, data);
        note.textContent = 'Saved graphic loaded into private preview.';
      } catch {
        note.textContent = 'That graphic could not be loaded.';
      }
    });

    library.querySelector('[data-effects-save]').addEventListener('click', () => {
      const name = graphicName.value.trim();
      if (!name) {
        graphicName.focus();
        note.textContent = 'Enter a name for this graphic.';
        return;
      }
      try {
        const entries = savedGraphics().filter(item => item.name !== name);
        const fields = Object.fromEntries(graphicFields.map(key => [key, field(key).value]));
        entries.push({ name, fields, loop: field('loop').checked,
          logo: motion.textKinds.has(fields.kind) ? logoData : null });
        localStorage.setItem(libraryKey, JSON.stringify(entries));
        updateLibrary(entries, name);
        note.textContent = 'Graphic saved to this browser.';
      } catch {
        note.textContent = 'The browser could not save this graphic.';
      }
    });

    deleteGraphic.addEventListener('click', () => {
      designRevision++;
      try {
        const entries = savedGraphics().filter(item => item.name !== saved.value);
        localStorage.setItem(libraryKey, JSON.stringify(entries));
        updateLibrary(entries);
        note.textContent = 'Graphic removed from saved graphics.';
      } catch {
        note.textContent = 'The browser could not remove this graphic.';
      }
    });

    function stopExport() {
      clearTimeout(exportTimer);
      exportWorker?.terminate();
      exportWorker = null;
      exportButton.disabled = false;
    }

    function clearDownload() {
      download.hidden = true;
      download.removeAttribute('href');
      if (downloadUrl) URL.revokeObjectURL(downloadUrl);
      downloadUrl = null;
    }

    exportButton.addEventListener('click', () => {
      if (exportWorker || field('kind').value === 'gif') return;
      const effect = cue();
      const count = Math.min(72, Math.round(effect.duration * .012));
      effect.start = 0;
      effect.loop = false;
      const frame = document.createElement('canvas');
      frame.width = 480;
      frame.height = 270;
      const ctx = frame.getContext('2d', { willReadFrequently: true });
      ctx.scale(frame.width / width, frame.height / height);
      const fail = error => {
        stopExport();
        note.textContent = error;
      };
      try {
        clearDownload();
        exportButton.disabled = true;
        note.textContent = 'Creating your GIF…';
        const encoder = exportWorker = new Worker('/lightek/live/effects-gif-export-worker.js?v=1');
        exportTimer = setTimeout(() => fail('GIF creation timed out.'), 20000);
        encoder.onerror = () => fail('The GIF encoder is unavailable.');
        encoder.onmessage = ({ data }) => {
          if (encoder !== exportWorker) return;
          if (data.error) return fail(data.error);
          if (data.bytes) {
            stopExport();
            downloadUrl = URL.createObjectURL(new Blob([data.bytes], { type: 'image/gif' }));
            download.href = downloadUrl;
            download.hidden = false;
            note.textContent = 'Your GIF is ready to save.';
            return;
          }
          ctx.clearRect(0, 0, width, height);
          render(ctx, effect, (data.frame + .5) / count * effect.duration);
          const rgba = ctx.getImageData(0, 0, frame.width, frame.height).data.buffer;
          encoder.postMessage({ type: 'frame', pixels: rgba }, [rgba]);
        };
        encoder.postMessage({ type: 'start', count });
      } catch {
        fail('GIF creation is unavailable in this browser.');
      }
    });

    function showDraft(now) {
      preview.clearRect(0, 0, width, height);
      if (render(preview, draft, now)) animationRequest = requestAnimationFrame(showDraft);
      else showPoster();
    }
    panel.querySelector('[data-effects-try]').addEventListener('click', () => {
      try {
        draft = cue();
        cancelAnimationFrame(animationRequest);
        showDraft(draft.start);
      } catch (error) { note.textContent = error.message; }
    });
    panel.querySelector('[data-effects-cue]').addEventListener('click', () => {
      try {
        program = cue();
        note.textContent = 'Effect cued on the program layer.';
      } catch (error) { note.textContent = error.message; }
    });

    function clear() {
      if (!program) return;
      program = null;
      note.textContent = 'Effects layer is clear.';
    }
    panel.querySelector('[data-effects-clear]').addEventListener('click', clear);
    const dispose = () => {
      revision++;
      designRevision++;
      cancelDecode();
      stopExport();
      clearDownload();
      clear();
      cancelAnimationFrame(animationRequest);
    };
    window.addEventListener('pagehide', dispose, { once: true });
    document.addEventListener('turbo:before-cache', dispose, { once: true });

    return {
      clear,
      draw(ctx, now) {
        if (!program) return;
        layerContext.clearRect(0, 0, width, height);
        if (render(layerContext, program, now)) ctx.drawImage(layer, 0, 0);
        else clear();
      }
    };
  }

  window.LightekLiveEffects = { boot };
})();
