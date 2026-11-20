(() => {
  function qrCard(url) {
    const qr = window.qrcode(0, 'M');
    qr.addData(url.href);
    qr.make();
    const count = qr.getModuleCount();
    const scale = Math.floor(190 / (count + 8));
    const card = document.createElement('canvas');
    card.width = (count + 8) * scale;
    card.height = card.width;
    const ctx = card.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, card.width, card.height);
    ctx.fillStyle = '#10151c';
    for (let row = 0; row < count; row++) {
      for (let column = 0; column < count; column++) {
        if (qr.isDark(row, column)) ctx.fillRect((column + 4) * scale, (row + 4) * scale, scale, scale);
      }
    }
    return card;
  }

  function boot(panel) {
    const toggle = panel.querySelector('[data-break-demo]');
    if (!toggle || typeof window.qrcode !== 'function') return null;
    const target = panel.querySelector('[data-break-demo-target]');
    let url, card;
    return {
      enabled: () => toggle.checked,
      target: () => target?.value,
      restore(enabled, url) {
        toggle.checked = enabled === true;
        if (target && Array.from(target.options).some(option => option.value === url)) target.value = url;
      },
      draw(ctx) {
        if (!toggle.checked) return;
        const selected = target?.value || toggle.dataset.breakDemo;
        if (url?.href !== selected) {
          url = new URL(selected);
          card = qrCard(url);
        }
        const heading = url.pathname === '/request-agency-demo' ? 'Request an agency demo' : 'Register for a demo';
        ctx.save();
        ctx.fillStyle = '#10151c';
        ctx.fillRect(966, 411, 282, 277);
        ctx.fillStyle = '#b5f58b';
        ctx.fillRect(966, 411, 282, 3);
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillStyle = '#fff';
        ctx.font = '700 26px system-ui';
        ctx.fillText(heading, 1107, 440, 250);
        ctx.drawImage(card, 1107 - Math.floor(card.width / 2), 461);
        ctx.font = '500 16px system-ui';
        ctx.fillText(url.host + url.pathname, 1107, 670, 250);
        ctx.restore();
      }
    };
  }
  window.LightekBreakDemo = { boot };
})();
