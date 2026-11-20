const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {JSDOM} = require('jsdom');
const {createCanvas, Image} = require('@napi-rs/canvas');

const markup = readFileSync('app/views/dashboard/live_broadcasts/_slate_design.html.erb', 'utf8')
  .replace('<%= @site.name %>', 'Customer Studio')
  .replace(/<% images = [\s\S]*?<label>Artwork fit/, `
    <select data-slate-field="logo"><option value=""></option><option value="18">Logo</option></select>
    <select data-slate-field="background"><option value=""></option><option value="24">Artwork</option></select>
    <label>Artwork fit`);
const dom = new JSDOM('<section data-break-scope="1:2">' + markup + '</section>', {
  url:'https://studio.test', runScripts:'outside-only'
});
const {window} = dom;
const draft = createCanvas(1280, 720);
const program = createCanvas(1280, 720);
window.document.querySelector('canvas').getContext = () => draft.getContext('2d');
function fixture(color) {
  const canvas = createCanvas(1280, 720);
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1280, 720);
  return canvas.toDataURL('image/png');
}
const sources = { '/api/lightek/pwa/assets/18/proxy': fixture('#ff7722'), '/api/lightek/pwa/assets/24/proxy': fixture('#113355') };
const pendingImages = [];
window.Image = class {
  constructor() {
    const image = new Image();
    const setter = Object.getOwnPropertyDescriptor(Image.prototype, 'src').set;
    Object.defineProperty(image, 'src', {set: value => {
      pendingImages.push(new Promise((resolve, reject) => {
        const loaded = image.onload;
        const failed = image.onerror;
        image.onload = () => { loaded(); resolve(); };
        image.onerror = error => { failed(error); reject(error); };
        setter.call(image, sources[value] || value);
      }));
    }});
    return image;
  }
};
const panel = window.document.querySelector('section');
const field = key => panel.querySelector('[data-slate-field="' + key + '"]');
const apply = () => panel.querySelector('[data-slate-apply]').click();
const pixel = (canvas, x, y) => Array.from(canvas.getContext('2d').getImageData(x, y, 1, 1).data);
const settle = async () => {
  await Promise.all(pendingImages);
  await new Promise(resolve => setImmediate(resolve));
};
window.eval(readFileSync('public/lightek/live/slate-design.js', 'utf8'));

(async () => {
  const slate = window.LightekSlateDesign.boot(panel, {brand:'Legacy Brand', heading:'Sponsor break', message:'Returning soon'});
  await settle();
  assert.equal(field('brand').value, 'Legacy Brand');
  slate.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 93, 271), [181, 245, 139, 255]);
  field('layout').value = 'centered';
  field('accent').value = '#f1a010';
  field('accent').dispatchEvent(new window.Event('input', {bubbles:true}));
  assert.deepEqual(pixel(draft, 640, 271), [241, 160, 16, 255]);
  slate.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 93, 271), [181, 245, 139, 255], 'draft does not modify the broadcast');
  field('logo').value = '18';
  field('background').value = '24';
  apply();
  await settle();
  slate.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 640, 108), [255, 119, 34, 255], 'use the Studio logo');
  assert.deepEqual(pixel(program, 640, 271), [241, 160, 16, 255]);
  assert.equal(JSON.parse(window.localStorage.getItem('lightek:slate-design:v1:1:2')).layout, 'centered');
  field('layout').value = 'artwork';
  field('background').value = '';
  apply();
  await settle();
  assert.match(panel.querySelector('[data-slate-status]').textContent, /Choose background/);
  slate.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 640, 108), [255, 119, 34, 255], 'invalid draft keeps the applied design');
  field('background').value = '24';
  apply();
  await settle();
  slate.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 640, 108), [17, 51, 85, 255], 'artwork only uses the full image without a logo or slate text');
  const reopened = window.LightekSlateDesign.boot(panel, {});
  await settle();
  reopened.draw(program.getContext('2d'));
  assert.deepEqual(pixel(program, 640, 271), [17, 51, 85, 255], 'reopening restores the applied slate');
  window.close();
  console.log('STUDIO_SLATE_DESIGN_PASS migration, draft isolation, logo, palette, artwork-only and reload');
})().catch(error => { console.error(error); window.close(); process.exitCode = 1; });
