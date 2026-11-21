const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { JSDOM } = require('jsdom');
const { createCanvas, Image } = require('@napi-rs/canvas');

const partial = readFileSync('app/views/dashboard/live_broadcasts/_broadcast_look.html.erb', 'utf8');
const themes = readFileSync('app/views/dashboard/live_broadcasts/_broadcast_themes.html.erb', 'utf8');
const markup = partial.replace(/<%= render "dashboard\/live_broadcasts\/broadcast_themes", kind: "(frame|background)" %>/g,
  (_, kind) => themes.replace('<%= kind %>', kind));
const dom = new JSDOM('<main>' + markup + '</main>', { runScripts: 'outside-only', url: 'https://studio.test' });
const { window } = dom;
const createElement = window.document.createElement.bind(window.document);
window.document.createElement = name => name === 'canvas' ? createCanvas(300, 150) : createElement(name);
const preview = createCanvas(1280, 720);
window.HTMLCanvasElement.prototype.getContext = () => preview.getContext('2d');
window.eval(readFileSync('public/lightek/live/broadcast-look.js', 'utf8'));
const root = window.document.querySelector('main');
const look = window.LightekBroadcastLook.boot(root);
const field = name => root.querySelector('[data-look="' + name + '"]');
const apply = () => root.querySelector('[data-apply-broadcast-look]').click();
const clear = () => root.querySelector('[data-clear-broadcast-look]').click();
const program = createCanvas(1280, 720);
const ctx = program.getContext('2d');
const pixel = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data);

for (const style of Array.from(field('frame').options, option => option.value).filter(style => style !== 'off')) {
  ctx.clearRect(0, 0, 1280, 720);
  field('frame').value = style;
  field('frame').dispatchEvent(new window.Event('change'));
  const scores = ['sports', 'gaming'].includes(style);
  assert.equal(root.querySelector('[data-look-score]').hidden, !scores);
  if (scores) field('score').value = 'ATL 24 · NY 17 · FINAL';
  field('frame-color').value = '#ff0000';
  field('headline').value = 'Come to Lightek!';
  apply();
  look.drawFrame(ctx);
  for (const [x, y] of [[640, 4], [640, 715], [4, 360], [1275, 360], [640, 360], [640, 100]]) {
    assert.equal(pixel(x, y)[3], 0, style + ' preserves the open program and the picture edges');
  }
  assert(pixel(40, 32)[3] > 65, style + ' draws a subtle inset bracket');
  const headlineX = style === 'sponsor' ? 1200 : ['cinema', 'entertainment'].includes(style) ? 640 : 68;
  assert(pixel(headlineX, 658)[3] > 230, style + ' draws its headline plate');
  const [red] = pixel(headlineX, 658);
  assert(red < 110, 'the chosen panel tint does not turn into an opaque red strip');
  const topX = ['studio', 'affiliate', 'sponsor'].includes(style) ? 1220 : 55;
  assert(pixel(topX, 55)[3] > 120, style + ' draws a compact identity plate');
  if (scores) assert(pixel(1190, 70)[3] > 230, 'sports score draws in the upper right');
}
field('frame').value = 'news';
field('texture').value = 'scanlines';
apply();
ctx.clearRect(0, 0, 1280, 720);
look.drawFrame(ctx);
const textured = pixel(80, 648);
field('texture').value = 'none';
apply();
ctx.clearRect(0, 0, 1280, 720);
look.drawFrame(ctx);
assert.notDeepEqual(pixel(80, 648), textured, 'the panel texture selector changes the rendered pixels');
assert.equal(pixel(700, 360)[3], 0, 'textures are confined to the graphic plates');

const camera = createCanvas(640, 360);
camera.videoWidth = 640;
camera.videoHeight = 360;
const cameraCtx = camera.getContext('2d');
const rect = [0, 0, 1280, 720];
field('frame').value = 'affiliate';
field('frame').dispatchEvent(new window.Event('change'));
assert(preview.getContext('2d').getImageData(1220, 55, 1, 1).data[3] > 0);
ctx.clearRect(0, 0, 1280, 720);
look.drawFrame(ctx);
assert.equal(pixel(1220, 55)[3], 0, 'draft station graphics stay private while the previous look is applied');

field('backdrop').value = 'sports';
apply();
cameraCtx.fillStyle = '#00b500';
cameraCtx.fillRect(0, 0, 640, 360);
cameraCtx.fillStyle = '#d85d40';
cameraCtx.fillRect(160, 90, 320, 180);
assert.equal(look.drawKeyedCamera(ctx, camera, rect, 0), true);
assert.deepEqual(pixel(640, 360), [216, 93, 64, 255], 'keep the presenter');
assert.notDeepEqual(pixel(20, 50), [0, 181, 0, 255], 'replace green pixels with studio backdrop');
const still = pixel(205, 180);
look.drawKeyedCamera(ctx, camera, rect, 3000);
assert.deepEqual(pixel(205, 180), still, 'motion off holds the backdrop steady');
field('motion').checked = true;
apply();
look.drawKeyedCamera(ctx, camera, rect, 3000);
assert.notDeepEqual(pixel(205, 180), still, 'motion on animates the background');

field('key').value = 'blue';
apply();
cameraCtx.fillStyle = '#0044ff';
cameraCtx.fillRect(0, 0, 640, 360);
look.drawKeyedCamera(ctx, camera, rect, 3000);
assert.notDeepEqual(pixel(640, 360), [0, 68, 255, 255], 'blue screen also keys out');

clear();
assert.equal(look.drawKeyedCamera(ctx, camera, rect, 0), false);
ctx.clearRect(0, 0, 1280, 720);
look.drawFrame(ctx);
assert.equal(pixel(0, 0)[3], 0, 'clear removes the frame');
const themeField = (kind, key) => root.querySelector('[data-look-themes="' + kind + '"] [data-theme-' + key + ']');
field('frame').value = 'news';
field('frame-color').value = '#32689e';
field('texture').value = 'brushed';
field('brand').value = 'Evening Desk';
themeField('frame', 'name').value = 'Evening';
themeField('frame', 'save').click();
field('backdrop').value = 'minimal';
field('speed').value = '1200';
field('motion').checked = true;
themeField('background', 'name').value = 'Evening';
themeField('background', 'save').click();

clear();
field('frame-color').value = '#111111';
field('speed').value = '2300';
field('motion').checked = false;
themeField('frame', 'load').click();
assert.equal(field('frame-color').value, '#32689e', 'load restores the saved palette');
assert.equal(field('brand').value, 'Evening Desk');
assert.equal(field('texture').value, 'brushed', 'theme restores the panel texture');
assert.equal(field('backdrop').value, 'off', 'loading the frame leaves the background draft alone');
look.drawFrame(ctx);
assert.equal(pixel(0, 0)[3], 0, 'loading a theme does not put it on air');
themeField('background', 'load').click();
assert.equal(field('backdrop').value, 'minimal');
assert.equal(field('speed').value, '1200');
assert.equal(field('motion').checked, true);
assert.equal(field('key').value, 'blue', 'loading a background retains the current camera calibration');
const key = 'lightek:broadcast-themes:v1:' + root.querySelector('[data-broadcast-look]').dataset.themeScope + ':frame';
const stored = JSON.parse(window.localStorage.getItem(key));
delete stored[0].values.texture;
window.localStorage.setItem(key, JSON.stringify(stored));
const reopened = root.cloneNode(true);
window.LightekBroadcastLook.boot(reopened);
const legacyList = reopened.querySelector('[data-look-themes="frame"] [data-theme-list]');
assert.equal(legacyList.options[1].value, 'Evening');
legacyList.value = 'Evening';
reopened.querySelector('[data-look="texture"]').value = 'none';
reopened.querySelector('[data-look-themes="frame"] [data-theme-load]').click();
assert.equal(reopened.querySelector('[data-look="texture"]').value, 'auto', 'older themes use the style texture');
themeField('frame', 'delete').click();
assert.equal(themeField('frame', 'list').options.length, 1, 'delete removes the frame theme');
assert.equal(themeField('background', 'list').options.length, 2, 'background theme remains available');
clear();

// Use a real decoded canvas image while simulating the browser's file picker.
const backdrop = createCanvas(12, 12);
const backdropCtx = backdrop.getContext('2d');
backdropCtx.fillStyle = '#aa33bb';
backdropCtx.fillRect(0, 0, 12, 12);
window.URL.createObjectURL = () => backdrop.toDataURL('image/png');
window.URL.revokeObjectURL = () => {};
window.Image = Image;
Object.defineProperty(field('image'), 'files', { value: [new window.File(['fixture'], 'set.png', { type: 'image/png' })] });
field('backdrop').value = 'image';
const notice = root.querySelector('[data-broadcast-look-status]');
const applied = new Promise((resolve, reject) => {
  const observer = new window.MutationObserver(() => {
    if (!notice.textContent.startsWith('Applied.')) return;
    clearTimeout(timeout);
    observer.disconnect();
    resolve();
  });
  const timeout = setTimeout(() => {
    observer.disconnect();
    reject(Error(notice.textContent));
  }, 4000);
  observer.observe(notice, { childList: true });
});
apply();

applied.then(async () => {
  assert.equal(look.drawKeyedCamera(ctx, camera, rect, 0), true);
  assert.deepEqual(pixel(640, 360), [170, 51, 187, 255], 'uploaded image fills the keyed background');
  const importer = themeField('frame', 'import');
  Object.defineProperty(importer, 'files', { value: [{ size: 345, text: async () => JSON.stringify({
    version: 1, name: 'Affiliate 12', values: {
      frame: 'affiliate', brand: 'Station 12', badge: '', accent: '#ffffff', 'frame-color': '#ececec', markers: false,
      headline: 'Do not import show copy'
    }
  }) }] });
  importer.dispatchEvent(new window.Event('change'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(field('brand').value, 'Station 12');
  assert.equal(field('headline').value, '');
  assert.equal(field('markers').checked, false);
  assert.match(themeField('frame', 'status').textContent, /private preview/);
  ctx.clearRect(0, 0, 1280, 720);
  look.drawFrame(ctx);
  assert.equal(pixel(1220, 55)[3], 0, 'import does not change the on-air overlay');
  themeField('frame', 'save').click();
  assert.equal(themeField('frame', 'list').value, 'Affiliate 12');
  let exported;
  window.URL.createObjectURL = blob => { exported = blob; return 'blob:fixture'; };
  window.HTMLAnchorElement.prototype.click = () => {};
  field('headline').value = 'Tonight’s live headline';
  themeField('frame', 'save').click();
  themeField('frame', 'export').click();
  const shared = await new Promise((resolve, reject) => {
    const reader = new window.FileReader();
    reader.onload = () => resolve(JSON.parse(reader.result));
    reader.onerror = reject;
    reader.readAsText(exported);
  });
  assert.equal(shared.version, 1);
  assert.equal(shared.name, 'Affiliate 12');
  assert.equal(shared.values['frame-color'], '#ececec');
  assert.equal(shared.values.markers, false);
  for (const key of ['headline', 'subtitle', 'score']) assert.equal(Object.hasOwn(shared.values, key), false);
  dom.window.close();
  console.log('STUDIO_LIVE_BROADCAST_LOOK_PASS inset frames, open picture, compact headline, textures, score, green and blue key, still and animated backdrops, local image');
}).catch(error => {
  dom.window.close();
  console.error(error);
  process.exitCode = 1;
});
