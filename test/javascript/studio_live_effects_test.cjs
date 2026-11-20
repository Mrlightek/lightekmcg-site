const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { JSDOM } = require('jsdom');
const { createCanvas, ImageData } = require('@napi-rs/canvas');
const { GifWriter } = require('../../public/lightek/vendor/omggif/omggif.js');

const source = name => readFileSync('public/lightek/live/' + name + '.js', 'utf8');
const markup = readFileSync('app/views/dashboard/live_broadcasts/_effects.html.erb', 'utf8');
const dom = new JSDOM('<main>' + markup + '</main>', { runScripts: 'outside-only', url: 'https://studio.test' });
const { window } = dom;
const root = window.document.querySelector('main');
const field = name => root.querySelector('[data-effect="' + name + '"]');
const draft = createCanvas(1280, 720);
root.querySelector('canvas').getContext = () => draft.getContext('2d');
const createElement = window.document.createElement.bind(window.document);
window.document.createElement = name => name === 'canvas' ? createCanvas(2, 2) : createElement(name);
window.ImageData = ImageData;
Object.defineProperty(window.performance, 'now', { value: () => 10000 });
window.requestAnimationFrame = () => 0;
window.cancelAnimationFrame = () => {};
window.Worker = class {
  postMessage(data) {
    const self = { postMessage: result => this.onmessage({ data: result }) };
    const decoder = readFileSync('public/lightek/vendor/omggif/omggif.js', 'utf8');
    runInNewContext(decoder + '\n' + source('effects-gif-worker'), { self, importScripts() {}, console });
    self.onmessage({ data });
  }
  terminate() {}
};
window.eval(source('effects'));
const effects = window.LightekLiveEffects.boot(root);
const program = createCanvas(1280, 720);
const ctx = program.getContext('2d');
const base = '#213243';
const blank = () => { ctx.fillStyle = base; ctx.fillRect(0, 0, 1280, 720); };
const pixel = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data);
const click = name => root.querySelector('[data-effects-' + name + ']').click();
const pixels = () => Buffer.from(ctx.getImageData(0, 0, 1280, 720).data);
blank();
const original = pixels();
click('try');
effects.draw(ctx, 10750);
assert.deepEqual(pixels(), original, 'private preview cannot touch the program');
click('cue');
effects.draw(ctx, 10750);
assert.notDeepEqual(pixels(), original, 'cue adds a transparent effect on program');
assert.deepEqual(pixel(0, 0), [33, 50, 67, 255], 'uncovered program is preserved');
blank();
effects.draw(ctx, 13000);
assert.deepEqual(pixels(), original, 'a one-shot effect expires');
field('loop').checked = true;
click('cue');
effects.draw(ctx, 13750);
assert.notDeepEqual(pixels(), original, 'looped cue repeats after its length');
click('clear');
blank();
effects.draw(ctx, 13750);
assert.deepEqual(pixels(), original, 'clear removes only the effect');

(async () => {
  // Two frames with a partial redraw and a transparent pixel in frame two.
  const buffer = new Uint8Array(256);
  const writer = new GifWriter(buffer, 2, 1, { palette: [0x000000, 0xff0000, 0x00ff00, 0xffffff] });
  writer.addFrame(0, 0, 2, 1, [1, 1], { delay:50, disposal:1 });
  writer.addFrame(0, 0, 2, 1, [2, 0], { delay:50, transparent:0 });
  const bytes = buffer.slice(0, writer.end());
  Object.defineProperty(field('file'), 'files', { value: [{ size:bytes.length, arrayBuffer:async () => bytes.buffer }] });
  field('file').dispatchEvent(new window.Event('change'));
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(field('kind').value, 'gif');
  assert.match(root.querySelector('[data-effects-status]').textContent, /GIF loaded/);
  field('opacity').value = '100';
  click('cue');
  blank();
  effects.draw(ctx, 10250);
  assert.deepEqual(pixel(490, 324), [255, 0, 0, 255]);
  blank();
  effects.draw(ctx, 10750);
  assert.deepEqual(pixel(490, 324), [0, 255, 0, 255], 'animation advances to a new GIF frame');
  assert.deepEqual(pixel(800, 324), [255, 0, 0, 255], 'a transparent GIF pixel retains the prior frame');
  click('clear');
  window.close();
  console.log('STUDIO_LIVE_EFFECTS_PASS private preview, transparent program layer, expiry, clear, and animated GIF');
})().catch(error => { window.close(); console.error(error); process.exitCode = 1; });
