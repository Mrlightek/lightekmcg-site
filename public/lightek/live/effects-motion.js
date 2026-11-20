(() => {
  const tau = Math.PI * 2;
  const unit = value => Math.max(0, Math.min(1, value));
  const ease = value => 1 - (1 - unit(value)) ** 3;
  const textKinds = new Set(['nameplate', 'opener']);

  const eases = new Set(['power2.out', 'sine.inOut', 'back.out(1.4)', 'none']);

  function animate(effect) {
    const length = effect.duration / 1000;
    const fit = Math.min(1, length * .88 / (effect.entrance + effect.exit));
    const entrance = effect.entrance * fit;
    const exit = effect.exit * fit;
    const stagger = Math.min(effect.stagger, entrance * .30);
    const frame = { plate: 0, edge: 0, heading: 0, subtitle: 0, logo: 0, exit: 1, travel: 0 };
    const gsap = window.gsap;
    if (!gsap) return progress => {
      const reveal = ease(progress * 6);
      return { plate: reveal, edge: reveal, heading: reveal, subtitle: reveal, logo: reveal,
        exit: ease((1 - progress) * 6), travel: ease(progress) };
    };

    const timeline = gsap.timeline({ paused: true });
    gsap.globalTimeline.remove(timeline);
    const reveal = (key, delay) => timeline.to(frame, {
      [key]: 1, duration: entrance - delay, ease: effect.easing
    }, delay);
    reveal('plate', 0);
    reveal('edge', stagger);
    reveal('heading', stagger * 2);
    reveal('subtitle', stagger * 3);
    reveal('logo', stagger);
    timeline.to(frame, { exit: 0, duration: exit, ease: 'power2.in' }, length - exit);
    timeline.to(frame, { travel: 1, duration: length, ease: 'power2.out' }, 0);
    return progress => {
      timeline.progress(progress, true);
      return frame;
    };
  }

  function title(ctx, effect, frame) {
    const { size, color, accent, title, subtitle, kind } = effect;
    const opener = kind === 'opener';
    const w = size;
    const h = w * (opener ? .37 : .245);
    const x = -w / 2, y = -h / 2;
    const slide = (1 - frame.plate + (1 - frame.exit) * .6) * w * .10;
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
    ctx.fillRect(x, y, w * unit(frame.edge), Math.max(2, h * .036));
    if (!opener) ctx.fillRect(x, y, Math.max(2, w * .009), h * unit(frame.edge));
    const pad = w * .047;
    const logo = effect.logo;
    const logoBox = logo ? w * .135 : 0;
    if (logo) {
      const scale = logoBox / Math.max(logo.width, logo.height);
      const logoWidth = logo.width * scale, logoHeight = logo.height * scale;
      ctx.save();
      ctx.globalAlpha *= unit(frame.logo);
      ctx.drawImage(logo, x + pad + (logoBox - logoWidth) / 2, -logoHeight / 2, logoWidth, logoHeight);
      ctx.restore();
    }
    const inset = logo ? logoBox + pad : 0;
    const textX = opener ? inset / 2 : x + pad + inset;
    const textWidth = w - pad * 2 - inset;
    ctx.textBaseline = 'middle';
    ctx.textAlign = opener ? 'center' : 'left';
    const alpha = ctx.globalAlpha;
    ctx.globalAlpha = alpha * unit(frame.heading);
    ctx.font = `700 ${Math.max(12, w * (opener ? .112 : .09))}px system-ui, sans-serif`;
    ctx.fillStyle = '#f9fbff';
    ctx.fillText(title, textX, (subtitle ? -h * .105 : 0) + (1 - frame.heading) * h * .2, textWidth);
    if (subtitle) {
      ctx.globalAlpha = alpha * unit(frame.subtitle);
      ctx.font = `500 ${Math.max(10, w * .04)}px system-ui, sans-serif`;
      ctx.fillStyle = '#cdd8e4';
      ctx.fillText(subtitle, textX, h * .24 + (1 - frame.subtitle) * h * .2, textWidth);
    }
  }

  function sweep(ctx, { size, color, accent }, progress) {
    ctx.rotate(-.26);
    const x = (progress - .5) * size * 1.18;
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

  function celebration(ctx, { size, color, accent }, progress, travel) {
    for (let i = 0; i < 42; i++) {
      const angle = i * 2.399963;
      const radius = size * travel * (.18 + (i % 9) / 26);
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
    const frame = effect.animation(progress);
    ctx.globalAlpha *= unit(frame.plate) * frame.exit;
    if (textKinds.has(effect.kind)) title(ctx, effect, frame);
    else if (effect.kind === 'sweep') sweep(ctx, effect, frame.travel);
    else if (effect.kind === 'confetti') celebration(ctx, effect, progress, frame.travel);
    else traces(ctx, effect, progress, effect.kind === 'rings');
  }

  window.LightekLiveMotion = { animate, draw, eases, textKinds };
})();
