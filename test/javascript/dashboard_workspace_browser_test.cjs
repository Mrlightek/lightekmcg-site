const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium, webkit } = require('playwright');
const root = path.resolve(__dirname, '../..');
const css = file => fs.readFileSync(path.join(root, 'public/lightek', file), 'utf8');
const palettes = [
  {name:'light', primary:'#172033', secondary:'#596579', panel:'#ffffff', page:'#f4f6fa', accent:'#2563eb', border:'#dce2eb'},
  {name:'dark', primary:'#edf1f7', secondary:'#aebacc', panel:'#181f2a', page:'#10151e', accent:'#8cb4ff', border:'#455269'}
];
function fixture(palette, reverse) {
  const sheets = ['production-workflow.css', 'reservations-workspace.css', 'site-content.css'];
  if(reverse) sheets.reverse();
  return `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><style>
  *{box-sizing:border-box}body{margin:0;font:14px system-ui;background:${palette.page};
  --dd-text-primary:${palette.primary};--dd-text-secondary:${palette.secondary};--dd-sidebar-bg:${palette.panel};--dd-page-bg:${palette.page};--dd-card-bg:${palette.page};--dd-accent:${palette.accent};--dd-border:${palette.border};--dd-input-bg:${palette.panel};--dd-input-text:${palette.primary};--dd-input-border:${palette.border};--dd-button-text:#fff}
  .dd-content{padding:20px}.lr-hero{display:flex;flex-wrap:wrap}.lr-admin-grid{display:grid}.lr-card{min-width:0}.lr-form{display:grid}.lr-stats{display:flex}.lr-stat{flex:1}
  ${sheets.map(css).join('\n')}</style><body class="dd-dashboard"><div class="dd-content">
  <main class="lr-admin"><nav class="production-navigation"><ol class="production-breadcrumbs"><li>Dashboard</li><li>Reservations</li></ol><div class="production-links"><a aria-current="page">Reservations</a><a>Rooms & guests</a><a>Live Studio</a></div></nav>
  <header class="lr-hero"><div><h1>Reservations</h1><p>Book appointments, reserve rooms and keep guests connected.</p></div><a class="lr-button">View booking page</a></header>
  <div class="lr-stats"><article class="lr-stat"><strong>0</strong><span>Upcoming</span></article></div><section class="lr-card"><h2>Create a bookable room</h2><p>Set availability for appointments.</p><form class="lr-form"><label>Website<select><option>Lightek</option></select></label><textarea>Booking notes</textarea></form><div class="booking-kind-picks"><button aria-pressed="true">Video room</button><button>Audio room</button></div></section></main>
  <main class="lt-settings content-hub"><h1>Design & Content</h1><p class="intro">Choose a website, preview a design.</p><section class="content-card"><h2>Site themes</h2><p>Install matching HTML pages as one website theme.</p><details open><summary>Build a website theme</summary><input value="My website"></details><a class="content-button primary">Open Pages & Sections</a></section><section class="card"><h2>Typography</h2><p>Font preview Aa Bb Cc</p><small>Choose a font family.</small></section><div class="tl-type-art" style="background:#123456;color:#fedcba">Design preview</div></main>
  </div></body>`;
}
(async()=>{
  for(const engine of [chromium,webkit]) {
    const browser = await engine.launch({headless:true});
    try {
      for(const palette of palettes) for(const reverse of [false,true]) for(const width of [1440,390]) {
        const page = await browser.newPage({viewport:{width,height:1000}});
        await page.setContent(fixture(palette,reverse));
        const actual = await page.evaluate(()=> {
          const value=(selector,property)=>getComputedStyle(document.querySelector(selector))[property];
          return {reservation:value('.lr-hero h1','color'),design:value('.content-hub h1','color'),panel:value('.content-card','backgroundColor'),helper:value('.content-card p','color'),breadcrumbs:value('.production-breadcrumbs','display'),backdrop:value('.lr-admin','backgroundColor'),preview:value('.tl-type-art','backgroundColor'),overflow:document.documentElement.scrollWidth>innerWidth};
        });
        const rgb = hex => `rgb(${hex.slice(1).match(/../g).map(x=>parseInt(x,16)).join(', ')})`;
        assert.equal(actual.reservation,rgb(palette.primary));
        assert.equal(actual.design,rgb(palette.primary));
        assert.equal(actual.panel,rgb(palette.panel));
        assert.equal(actual.helper,rgb(palette.secondary));
        assert.equal(actual.backdrop,'rgba(0, 0, 0, 0)');
        assert.equal(actual.breadcrumbs,'none');
        assert.equal(actual.preview,'rgb(18, 52, 86)');
        assert.equal(actual.overflow,false,`${palette.name} ${width}: page overflows`);
        await page.close();
      }
    } finally {await browser.close();}
  }
  console.log('Dashboard workspaces: Chromium/WebKit, light/dark, desktop/mobile, both stylesheet orders passed');
})().catch(error=>{console.error(error);process.exitCode=1});
