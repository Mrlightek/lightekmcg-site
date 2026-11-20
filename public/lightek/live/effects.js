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
    let program, draft, animationRequest, gif, worker, revision = 0, workerTimer, displayedFrame;
    let exportWorker, exportTimer, downloadUrl;

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
      const pct = (name, fallback) => Math.max(0, Math.min(100, Number(field(name).value) || fallback)) / 100;
      return {
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
        loop: field('loop').checked,
        duration: Math.max(1, Math.min(30, Number(field('seconds').value) || 3)) * 1000,
        start: performance.now()
      };
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
      render(preview, sample, sample.start + sample.duration * .42);
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
      exportButton.hidden = kind === 'gif';
      showPoster();
    }
    field('kind').addEventListener('change', selectPreset);
    panel.addEventListener('input', event => {
      if (event.target.matches('input[data-effect]:not([type="file"])')) showPoster();
    });
    selectPreset();

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
