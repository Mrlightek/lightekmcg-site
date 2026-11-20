const assert = require('node:assert/strict');
const fs = require('node:fs');
const { JSDOM } = require('jsdom');
const { createCanvas } = require('@napi-rs/canvas');

const view = fs.readFileSync('app/views/dashboard/live_broadcasts/_program_graphics.html.erb', 'utf8');
const dom = new JSDOM('<main>' + view + '</main>', { runScripts: 'outside-only' });
const { window } = dom;
window.eval(fs.readFileSync('public/lightek/live/graphics.js', 'utf8'));
const root = window.document.querySelector('main');
const field = name => root.querySelector('[data-graphic="' + name + '"]');
const show = root.querySelector('[data-show-graphic]');
const hide = root.querySelector('[data-hide-graphic]');
const graphic = window.LightekLiveGraphics.boot(root);
const ctx = createCanvas(1280, 720).getContext('2d');
const pixel = (x, y) => Array.from(ctx.getImageData(x, y, 1, 1).data);

show.click();
assert.equal(hide.disabled, true, 'blank titles stay off program');
field('title').value = 'Building Lightek';
field('subtitle').value = 'Live Studio';
field('accent').value = '#ff2200';

for (const [layout, x, y] of [['lower', 43, 421], ['corner', 43, 43], ['title', 201, 276]]) {
  ctx.clearRect(0, 0, 1280, 720);
  field('layout').value = layout;
  show.click();
  graphic.draw(ctx);
  assert.deepEqual(pixel(x, y), [255, 34, 0, 255]);
  assert.equal(hide.disabled, false);
}

hide.click();
ctx.clearRect(0, 0, 1280, 720);
graphic.draw(ctx);
assert.deepEqual(pixel(201, 276), [0, 0, 0, 0]);
dom.window.close();
console.log('STUDIO_LIVE_GRAPHICS_PASS cue, placement, accent and hide on a program canvas');
