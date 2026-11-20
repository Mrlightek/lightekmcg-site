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
const work = createCanvas(300, 150);
window.document.createElement = name => name === 'canvas' ? work : createElement(name);
window.eval(readFileSync('public/lightek/live/broadcast-look.js', 'utf8'));
const root = window.document.querySelector('main');
const look = window.LightekBroadcastLook.boot(root);
const field = name => root.querySelector('[data-look="' + name + '"]');
const apply = () => root.querySelector('[data-apply-broadcast-look]').click();
const clear = () => root.querySelector('[data-clear-broadcast-look]').click();
const program = createCanvas(1280, 720);
const ctx = program.getContext('2d');
const pixel = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data);

for (const style of ['news', 'sports']) {
  ctx.clearRect(0, 0, 1280, 720);
  field('frame').value = style;
  apply();
  look.drawFrame(ctx);
  for (const [x, y] of [[640, 4], [640, 715], [4, 360], [1275, 360]]) {
    assert.equal(pixel(x, y)[3], 255, style + ' covers all four edges');
  }
  assert.equal(pixel(640, 360)[3], 0, style + ' leaves the program picture open');
}

const camera = createCanvas(640, 360);
camera.videoWidth = 640;
camera.videoHeight = 360;
const cameraCtx = camera.getContext('2d');
const rect = [0, 0, 1280, 720];
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
assert.equal(field('backdrop').value, 'off', 'loading the frame leaves the background draft alone');
look.drawFrame(ctx);
assert.equal(pixel(0, 0)[3], 0, 'loading a theme does not put it on air');
themeField('background', 'load').click();
assert.equal(field('backdrop').value, 'minimal');
assert.equal(field('speed').value, '1200');
assert.equal(field('motion').checked, true);
assert.equal(field('key').value, 'blue', 'loading a background retains the current camera calibration');
const reopened = root.cloneNode(true);
window.LightekBroadcastLook.boot(reopened);
assert.equal(reopened.querySelector('[data-look-themes="frame"] [data-theme-list]').options[1].value, 'Evening');
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

applied.then(() => {
  assert.equal(look.drawKeyedCamera(ctx, camera, rect, 0), true);
  assert.deepEqual(pixel(640, 360), [170, 51, 187, 255], 'uploaded image fills the keyed background');
  dom.window.close();
  console.log('STUDIO_LIVE_BROADCAST_LOOK_PASS four frame edges, transparent center, green and blue key, still and animated backdrops, local image');
}).catch(error => {
  dom.window.close();
  console.error(error);
  process.exitCode = 1;
});
