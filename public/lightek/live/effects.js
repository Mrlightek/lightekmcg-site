(() => {
  const width = 1280, height = 720;

  function drawMotion(ctx, effect, progress) {
    const { size, kind, color } = effect;
    ctx.fillStyle = color;
    if (kind === 'sweep') {
      const offset = (progress - .5) * size * 1.8;
      ctx.rotate(-.35);
      const gradient = ctx.createLinearGradient(offset - size / 5, 0, offset + size / 5, 0);
      gradient.addColorStop(0, color + '00');
      gradient.addColorStop(.5, color);
      gradient.addColorStop(1, color + '00');
      ctx.fillStyle = gradient;
      ctx.fillRect(offset - size / 5, -size / 2, size * .4, size);
      return;
    }
    const confetti = kind === 'confetti';
    for (let i = 0; i < 32; i++) {
      const phase = i * 2.399963;
      const radius = size * progress * (.18 + (i % 9) / 27);
      const x = Math.cos(phase) * radius;
      const y = Math.sin(phase) * radius + (confetti ? size * progress ** 2 * .6 : 0);
      const dot = Math.max(2, size * (.006 + (i % 4) * .003));
      ctx.fillStyle = confetti && i % 3 ? (i % 3 === 1 ? '#f5f7ff' : '#78d8ff') : color;
      ctx.fillRect(x, y, dot * (confetti ? 1.8 : 1), dot);
    }
  }

  function boot(root) {
    const panel = root.querySelector('[data-live-effects]');
    if (!panel) return null;
    const field = name => panel.querySelector('[data-effect="' + name + '"]');
    const note = panel.querySelector('[data-effects-status]');
    const preview = panel.querySelector('[data-effects-preview]').getContext('2d');
    const layer = document.createElement('canvas');
    layer.width = width;
    layer.height = height;
    const layerContext = layer.getContext('2d');
    const gifCanvas = document.createElement('canvas');
    const gifContext = gifCanvas.getContext('2d');
    let program, draft, animationRequest, gif, worker, revision = 0, workerTimer, displayedFrame;

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
        ctx.globalAlpha *= Math.min(1, progress * 8, (1 - progress) * 4);
        drawMotion(ctx, cue, progress);
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
      field('kind').value = 'gif';
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
          field('seconds').value = Math.max(1, Math.min(30, Math.round(duration / 1000)));
          note.textContent = 'GIF loaded. Preview it or cue it on program.';
        };
        decoder.postMessage(data, [data]);
      } catch {
        if (revision === current) note.textContent = 'The GIF file could not be opened.';
      }
    });

    function showDraft(now) {
      preview.clearRect(0, 0, width, height);
      if (render(preview, draft, now)) animationRequest = requestAnimationFrame(showDraft);
      else draft = null;
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
