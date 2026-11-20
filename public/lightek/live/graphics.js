/* Draw operator-cued titles in the same canvas used by preview and broadcast. */
(() => {
  const layouts = {
    lower: { x: 42, y: 420, width: 650, height: 112, size: 38 },
    corner: { x: 42, y: 42, width: 440, height: 100, size: 30 },
    title: { x: 200, y: 275, width: 880, height: 148, size: 48 }
  };

  function draw(ctx, graphic, featuredComment) {
    if (!graphic) return;
    const { x, y: defaultY, width, height, size } = layouts[graphic.layout];
    const y = featuredComment && graphic.layout === 'lower' ? 380 : defaultY;
    ctx.save();
    ctx.filter = 'none';
    ctx.globalAlpha = 1;
    ctx.textAlign = graphic.layout === 'title' ? 'center' : 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = 'rgba(11,18,27,.96)';
    ctx.fillRect(x, y, width, height);
    ctx.fillStyle = graphic.accent;
    ctx.fillRect(x, y, 6, height);
    const textX = graphic.layout === 'title' ? x + width / 2 : x + 26;
    ctx.fillStyle = '#fff';
    ctx.font = '700 ' + size + 'px system-ui';
    ctx.fillText(graphic.title, textX, y + height * (graphic.subtitle ? .38 : .5), width - 52);
    if (graphic.subtitle) {
      ctx.fillStyle = '#d9e2ed';
      ctx.font = '500 23px system-ui';
      ctx.fillText(graphic.subtitle, textX, y + height * .72, width - 52);
    }
    ctx.restore();
  }

  function boot(root) {
    const panel = root.querySelector('[data-live-graphics]');
    if (!panel) return null;
    const field = name => panel.querySelector('[data-graphic="' + name + '"]');
    const hide = panel.querySelector('[data-hide-graphic]');
    const status = panel.querySelector('[data-graphic-status]');
    let graphic = null;
    panel.querySelector('[data-show-graphic]').addEventListener('click', () => {
      const title = field('title').value.trim().slice(0, 80);
      if (!title) {
        status.textContent = 'Enter a title before showing the graphic.';
        field('title').focus();
        return;
      }
      const layout = field('layout').value;
      const accent = field('accent').value;
      graphic = {
        title,
        subtitle: field('subtitle').value.trim().slice(0, 120),
        layout: Object.hasOwn(layouts, layout) ? layout : 'lower',
        accent: /^#[0-9a-f]{6}$/i.test(accent) ? accent : '#b5f58b'
      };
      hide.disabled = false;
      status.textContent = 'Graphic shown when the program picture is active.';
    });
    function clear() {
      graphic = null;
      hide.disabled = true;
      status.textContent = 'Graphic hidden.';
    }
    hide.addEventListener('click', clear);
    return { draw: (ctx, featuredComment) => draw(ctx, graphic, featuredComment), clear };
  }

  window.LightekLiveGraphics = { boot };
})();
