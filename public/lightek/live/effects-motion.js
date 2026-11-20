(() => {
  const tau = Math.PI * 2;
  const unit = value => Math.max(0, Math.min(1, value));
  const ease = value => 1 - (1 - unit(value)) ** 3;
  const fade = progress => Math.min(ease(progress * 8), ease((1 - progress) * 6));
  const textKinds = new Set(['nameplate', 'opener']);

  function title(ctx, effect, progress) {
    const { size, color, accent, title, subtitle, kind } = effect;
    const opener = kind === 'opener';
    const w = size;
    const h = w * (opener ? .37 : .245);
    const x = -w / 2, y = -h / 2;
    const slide = (1 - ease(progress * 6)) * w * .07;
    ctx.translate(opener ? 0 : -slide, opener ? slide : 0);
    const plate = ctx.createLinearGradient(x, 0, x + w, h);
    plate.addColorStop(0, '#101722');
    plate.addColorStop(.84, '#172431');
    plate.addColorStop(1, '#1d2d3c');
    ctx.fillStyle = plate;
    ctx.fillRect(x, y, w, h);

    const edge = ctx.createLinearGradient(x, y, x + w, y);
    edge.addColorStop(0, color);
    edge.addColorStop(.7, accent);
    edge.addColorStop(1, accent + '20');
    ctx.fillStyle = edge;
    ctx.fillRect(x, y, w * ease(progress * 5), Math.max(2, h * .036));
    if (!opener) ctx.fillRect(x, y, Math.max(2, w * .009), h);
    const pad = w * .047;
    ctx.textBaseline = 'middle';
    ctx.textAlign = opener ? 'center' : 'left';
    ctx.font = `700 ${Math.max(12, w * (opener ? .112 : .09))}px system-ui, sans-serif`;
    ctx.fillStyle = '#f9fbff';
    ctx.fillText(title, opener ? 0 : x + pad, subtitle ? -h * .105 : 0, w - pad * 2);
    if (subtitle) {
      ctx.font = `500 ${Math.max(10, w * .04)}px system-ui, sans-serif`;
      ctx.fillStyle = '#cdd8e4';
      ctx.fillText(subtitle, opener ? 0 : x + pad, h * .24, w - pad * 2);
    }
  }

  function sweep(ctx, { size, color, accent }, progress) {
    ctx.rotate(-.26);
    const x = (ease(progress) - .5) * size * 1.18;
    const gradient = ctx.createLinearGradient(x - size * .42, 0, x + size * .42, 0);
    gradient.addColorStop(0, color + '00');
    gradient.addColorStop(.34, color + '35');
    gradient.addColorStop(.53, accent + 'db');
    gradient.addColorStop(.68, color + '55');
    gradient.addColorStop(1, color + '00');
    ctx.scale(1, .32);
    ctx.fillStyle = gradient;
    ctx.beginPath();
    ctx.ellipse(x, 0, size * .43, size * .43, 0, 0, tau);
    ctx.fill();
    ctx.fillStyle = accent + 'bd';
    ctx.beginPath();
    ctx.ellipse(x, 0, size * .25, size * .018, 0, 0, tau);
    ctx.fill();
  }

  function traces(ctx, { size, color, accent }, progress, rings) {
    ctx.rotate(rings ? -.21 : -.43);
    ctx.lineCap = 'round';
    for (let i = 0; i < 4; i++) {
      const radius = size * (.17 + i * .072);
      const gradient = ctx.createLinearGradient(-radius, -radius, radius, radius);
      gradient.addColorStop(0, color + '00');
      gradient.addColorStop(.4, color + 'bd');
      gradient.addColorStop(.7, accent);
      gradient.addColorStop(1, accent + '04');
      ctx.strokeStyle = gradient;
      ctx.lineWidth = Math.max(1, size * (.008 - i * .001));
      ctx.beginPath();
      const angle = progress * (rings ? Math.PI : tau) + i * .7;
      ctx.ellipse(0, 0, radius, radius * (rings ? .9 : .35), i * .16, angle, angle + (rings ? 4.4 : 2.8));
      ctx.stroke();
    }
  }

  function celebration(ctx, { size, color, accent }, progress) {
    const motion = ease(progress);
    for (let i = 0; i < 42; i++) {
      const angle = i * 2.399963;
      const radius = size * motion * (.18 + (i % 9) / 26);
      const x = Math.cos(angle) * radius;
      const y = Math.sin(angle) * radius + size * progress ** 2 * .22;
      const weight = Math.max(1.2, size * (.004 + (i % 4) * .002));
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(angle + progress * 3);
      ctx.fillStyle = [color, accent, '#e7edf2'][i % 3];
      ctx.beginPath();
      ctx.ellipse(0, 0, weight * (1.4 + i % 2), weight * .38, 0, 0, tau);
      ctx.fill();
      ctx.restore();
    }
  }

  function draw(ctx, effect, progress) {
    ctx.globalAlpha *= fade(progress);
    if (textKinds.has(effect.kind)) title(ctx, effect, progress);
    else if (effect.kind === 'sweep') sweep(ctx, effect, progress);
    else if (effect.kind === 'confetti') celebration(ctx, effect, progress);
    else traces(ctx, effect, progress, effect.kind === 'rings');
  }

  window.LightekLiveMotion = { draw, textKinds };
})();
