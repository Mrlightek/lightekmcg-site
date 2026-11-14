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
  const sheets = ['production-workflow.css', 'reservations-workspace.css', 'site-content.css','broadcast/control.css','media-control.css','business-workspace.css','studio-editors.css'];
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
  <main class="media-control"><header class="mc-top"><span class="mc-brand">MEDIA STUDIO</span><nav><a class="mc-button">Live Studio</a><a class="mc-button mc-primary">New production</a></nav></header>
  <section class="mc-intro"><div><h1>Make something worth watching.</h1><p>Open a production from your library.</p></div><form class="mc-selector"><div class="mc-field"><label for="workspace">Workspace <button type="button" style="height:22px;width:22px;padding:0">i</button></label><select id="workspace"><option>Lightek</option></select></div><input type="submit" value="Switch"></form></section>
  <div class="mc-library-toolbar"><h2>Production library</h2><span>6 productions</span></div><section class="mc-project-grid"><article class="mc-project mc-new"><h3>New production</h3><p>Edit your next story.</p><a class="mc-button mc-primary">Create production</a></article><article class="mc-project"><a class="mc-project-image"><span>NP</span><small>PRODUCTION</small></a><div class="mc-project-info"><h3>New Project</h3><p>1 scene</p><a class="mc-button">Open Media Studio</a><a class="mc-project-delete">Delete project</a></div></article></section>
  <details class="mc-broadcast-settings" open><summary>Broadcast management</summary><section class="ms-card"><h2>Media & releases</h2><p class="ms-muted">Choose an export.</p><a class="ms-button ms-primary">Queue release</a></section></details></main>
  <main class="studio-editor-launch"><nav class="business-workspace"><div class="business-workspace-links"><a href="#business">Business</a><a href="#studio" aria-current="page">Studio</a></div></nav><header><h1>Make something worth sharing.</h1></header><nav class="studio-editor-types" aria-label="Editor type"><a aria-current="page">Photo & graphics</a><a>Video & audio</a></nav><form><label>Project name<input placeholder="Our next story"></label><select><option>Landscape</option></select><input type="submit" value="Open Photo Studio"></form><p><a href="#productions">Back to productions</a></p></main>
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
          return {reservation:value('.lr-hero h1','color'),design:value('.content-hub h1','color'),panel:value('.content-card','backgroundColor'),helper:value('.content-card p','color'),breadcrumbs:value('.production-breadcrumbs','display'),backdrop:value('.lr-admin','backgroundColor'),preview:value('.tl-type-art','backgroundColor'),studioHeading:value('.mc-intro h1','color'),studioHeader:value('.mc-top','backgroundColor'),studioCard:value('.mc-project','backgroundColor'),studioHelper:value('.mc-project-info p','color'),studioRelease:value('.ms-card','backgroundColor'),businessLink:value('.studio-editor-launch .business-workspace a','backgroundColor'),backLink:value('.studio-editor-launch>p>a','color'),pickerGap:Math.abs(document.querySelector('.mc-selector select').getBoundingClientRect().bottom-document.querySelector('.mc-selector input').getBoundingClientRect().bottom),overflow:document.documentElement.scrollWidth>innerWidth};
        });
        const rgb = hex => `rgb(${hex.slice(1).match(/../g).map(x=>parseInt(x,16)).join(', ')})`;
        assert.equal(actual.reservation,rgb(palette.primary));
        assert.equal(actual.design,rgb(palette.primary));
        assert.equal(actual.panel,rgb(palette.panel));
        assert.equal(actual.helper,rgb(palette.secondary));
        assert.equal(actual.backdrop,'rgba(0, 0, 0, 0)');
        assert.equal(actual.breadcrumbs,'none');
        assert.equal(actual.preview,'rgb(18, 52, 86)');
        assert.equal(actual.studioHeading,rgb(palette.primary));
        assert.equal(actual.studioHeader,rgb(palette.panel));
        assert.equal(actual.studioCard,rgb(palette.panel));
        assert.equal(actual.studioHelper,rgb(palette.secondary));
        assert.equal(actual.studioRelease,rgb(palette.panel));
        assert.equal(actual.businessLink,'rgba(0, 0, 0, 0)');
        assert.equal(actual.backLink,rgb(palette.accent));
        if(width>=850) assert(actual.pickerGap<2, 'Workspace switch must align with its select');
        assert.equal(actual.overflow,false,`${palette.name} ${width}: page overflows`);
        await page.close();
      }
    } finally {await browser.close();}
  }
  console.log('Dashboard workspaces: Chromium/WebKit, light/dark, desktop/mobile, both stylesheet orders passed');
})().catch(error=>{console.error(error);process.exitCode=1});
