const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const drivers = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '../..');
const fixtureDir = process.env.DASHBOARD_FORM_FIXTURES || '/tmp/lightek-form-fixtures';
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const base = read('app/views/dymond_dash/layouts/dymond_dash.html.erb').match(/<style>([\s\S]*?)<\/style>/)[1];
const theme = fs.readFileSync(path.join(fixtureDir, 'theme.css'), 'utf8');
const css = read('public/lightek/dashboard.css') + read('public/lightek/dashboard-forms.css');
const js = read('public/lightek/dashboard.js');
const palettes = {
  light: {},
  dark: {'page-bg':'#10151e','sidebar-bg':'#181f2a','topbar-bg':'#181f2a','card-bg':'#1c2634','text-primary':'#edf1f7','text-secondary':'#aebacc','text-muted':'#aebacc','border':'#455269','input-bg':'#111924','input-text':'#edf1f7','input-border':'#596a82','accent':'#8cb4ff','accent-hover':'#abc8ff','button-text':'#000000','button-hover-text':'#000000','danger':'#f48d96','success':'#6ed8ac','form-scheme':'dark'}
};
function fixture(view, palette) {
  const vars = Object.entries(palettes[palette]).map(([key,value])=>`--dd-${key}:${value}`).join(';');
  return `<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>${base}${theme}${css}</style></head><body class="dd-dashboard" style="${vars}"><div class="dd-shell"><aside class="dd-sidebar"><div class="dd-brand"><a class="dd-brand-name">LIGHTEK</a><div class="dd-brand-sub">Business operating system</div></div><nav class="dd-nav"><div class="dd-nav-label">Workspaces</div><a class="dd-nav-item">Overview</a><a class="dd-nav-item active">Commerce</a><a class="dd-nav-item">Reservations & experiences</a><a class="dd-nav-item">Design & content</a></nav></aside><div class="dd-body"><div class="dd-topbar"><span class="dd-breadcrumbs">Dashboard › Commerce › ${view === 'orders' ? 'Orders' : 'Edit product'}</span></div><div class="dd-content">${fs.readFileSync(path.join(fixtureDir,view+'.html'),'utf8')}</div></div></div><script>${js}</script></body></html>`;
}
module.exports = {fixture};
if (require.main === module) (async()=> {
  let checked = 0;
  for(const driver of (process.env.DASHBOARD_BROWSERS || 'chromium,webkit').split(',')) {
    const browser = await drivers[driver].launch({headless:true,...(driver==='chromium' && process.env.CHROMIUM_EXECUTABLE ? {executablePath:process.env.CHROMIUM_EXECUTABLE,args:['--no-sandbox']} : {})});
    try {
      for(const palette of Object.keys(palettes)) for(const width of [1440,390]) for(const view of ['orders','product']) {
        const page = await browser.newPage({viewport:{width,height:1000}});
        await page.setContent(fixture(view,palette));
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${view} ${palette} ${width}: page overflow`);
        if(view==='orders') {
          assert(await page.locator('[data-order-bulk-delete]').isDisabled());
          await page.locator('[data-order-select-all]').check();
          assert.equal(await page.locator('[data-order-select]:checked').count(),2);
          assert.equal(await page.locator('[data-order-selection-count]').textContent(),'2 unpaid orders selected');
          assert(!(await page.locator('[data-order-bulk-delete]').isDisabled()));
          await page.locator('[data-order-select]').first().uncheck();
          assert(await page.locator('[data-order-select-all]').evaluate(el=>el.indeterminate));
          await page.locator('details.dd-order-manage').first().locator('summary').click();
          assert(await page.locator('[name=fulfillment_reference]').isVisible());
          const sizes = await page.locator('.dd-order-panels input:not([type=hidden])').evaluateAll(els=>els.map(el=>({field:el.getBoundingClientRect().toJSON(),panel:el.closest('.dd-form-section').getBoundingClientRect().toJSON()})));
          for(const {field,panel} of sizes) assert(field.left>=panel.left && field.right<=panel.right+1,'Field escapes its form panel');
        } else {
          await page.locator('#product_name').fill('Lightek Studio plan');
          await page.locator('#product_published').uncheck();
          assert.equal(await page.locator('#product_published').isChecked(),false);
          const box = await page.locator('#product_published').boundingBox();
          assert(box.width<=24 && box.height<=24,'Checkbox must not stretch like a text field');
          const errors = await page.evaluate(()=>[...document.querySelectorAll('input:not([type=hidden]):not([type=submit]),select,textarea')].filter(el=>!el.labels?.length && !el.getAttribute('aria-label')).map(el=>el.name));
          assert.deepEqual(errors,[],'Every editable field needs a label');
        }
        assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`${view} ${palette} ${width}: expanded form overflow`);
        const colors = await page.locator('.dd-btn-primary').first().evaluate(el=>({fg:getComputedStyle(el).color,bg:getComputedStyle(el).backgroundColor}));
        function luminance(rgb) { return rgb.match(/[\d.]+/g).slice(0,3).map(Number).map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0); }
        const l = [luminance(colors.fg),luminance(colors.bg)].sort((a,b)=>b-a);
        assert((l[0]+.05)/(l[1]+.05)>=4.5,'Primary action contrast');
        if(process.env.DASHBOARD_SCREENSHOTS && driver==='chromium') {
          fs.mkdirSync(process.env.DASHBOARD_SCREENSHOTS,{recursive:true});
          await page.screenshot({path:path.join(process.env.DASHBOARD_SCREENSHOTS,`${view}-${palette}-${width}.png`),fullPage:true});
        }
        checked++; await page.close();
      }
    } finally { await browser.close(); }
  }
  console.log(`Dashboard forms: ${checked} real-view browser checks passed`);
})().catch(error=>{console.error(error);process.exitCode=1});
