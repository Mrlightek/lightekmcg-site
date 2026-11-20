const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {JSDOM} = require('jsdom');
const {createCanvas} = require('@napi-rs/canvas');
const {window} = new JSDOM(`<div data-holding-break data-break-brand="Client Studio" data-break-scope="1:2">
  <input value="Client Studio" data-break-brand-input><input value="Back in a moment." data-break-heading>
  <input value="Stay with us." data-break-message>
  <select data-break-item><option value="15" data-kind="image">Ad</option></select>
  <select data-break-item><option value="24" data-kind="video">Commercial</option></select>
  <select data-break-music><option value="19">Music</option></select>
  <input value="0.25" data-break-volume><button data-break-save></button><button data-break-next></button>
  <input type="checkbox" data-break-demo="https://demo.example.test/request-demo">
  <select data-break-demo-target><option value="https://demo.example.test/request-demo">Client</option>
  <option value="https://demo.example.test/request-agency-demo">Agency</option></select><span data-break-status></span></div>`, {url:'https://studio.test', runScripts:'outside-only'});
const created = [];
const createElement = window.document.createElement.bind(window.document);
window.document.createElement = name => {
  if (name === "canvas") return createCanvas(1, 1);
  const el = createElement(name);
  created.push(el);
  el.play = () => Promise.resolve();
  el.pause = () => {};
  el.load = () => {};
  Object.defineProperty(el, name === 'video' ? 'videoWidth' : 'naturalWidth', {value:640});
  Object.defineProperty(el, name === 'video' ? 'videoHeight' : 'naturalHeight', {value:360});
  return el;
};
const gains = [];
const context = {
  createMediaElementSource() { return {connect: target => target, disconnect() {}}; },
  createGain() {
    const node = {gain:{value:0}, connect() {}, disconnect() {}};
    gains.push(node);
    return node;
  }
};
const lines = [], pictures = [];
const canvas = {save() {}, restore() {}, fillRect() {}, fillText: (...args) => lines.push(args[0]), drawImage: (...args) => pictures.push(args)};
const event = name => new window.Event(name);
window.eval(readFileSync('public/lightek/vendor/qrcode-generator/qrcode.js','utf8'));
window.eval(readFileSync('public/lightek/live/break-demo.js','utf8'));
window.eval(readFileSync('public/lightek/live/holding-break.js','utf8'));
const q = selector => window.document.querySelector(selector);
const studio = window.LightekHoldingBreak.boot(window.document);
studio.draw(canvas);
assert.deepEqual(lines, ['Client Studio', 'Back in a moment.', 'Stay with us.']);
assert.equal(created.length, 0, 'an automatic hold depicts the slate without starting a paid break');
q('[data-break-heading]').value = 'Sponsor break';
q('[data-break-demo]').checked = true;
q('[data-break-save]').click();
studio.draw(canvas);
assert.equal(pictures.length, 0, 'automatic holds have no demo overlay');
assert.equal(JSON.parse(window.localStorage.getItem('lightek:holding-break:v1:1:2')).demo, true);
assert.equal(JSON.parse(window.localStorage.getItem('lightek:holding-break:v1:1:2')).heading, 'Sponsor break');
studio.start(context, {});
const [music, image] = created;
assert.equal(music.getAttribute('src'), '/api/lightek/pwa/assets/19/proxy');
assert.equal(gains[0].gain.value, .25);
image.dispatchEvent(event('load'));
studio.draw(canvas);
assert.equal(pictures[0][0], image);
assert.match(lines.join(' '), /Register for a demo/);
assert.match(lines.join(' '), /demo.example.test\/request-demo/);
const qr = pictures[1][0];
const pixels = qr.getContext('2d');
assert.deepEqual(Array.from(pixels.getImageData(0,0,1,1).data), [255,255,255,255]);
assert.equal(Array.from(pixels.getImageData(35,35,1,1).data)[3], 255);
q('[data-break-demo]').checked = false;
q('[data-break-next]').click();
const video = created[2];
assert.equal(gains[0].gain.value, 0, 'music is ducked while the commercial is queued');
video.dispatchEvent(event('canplay'));
assert.equal(gains[1].gain.value, 1);
video.dispatchEvent(event('ended'));
studio.draw(canvas);
assert.equal(pictures.length, 2);
assert.equal(gains[1].gain.value, 0);
assert.equal(gains[0].gain.value, .25, 'music returns with the slate');
studio.stop();
assert.equal(gains[0].gain.value, 0);
assert.equal(music.hasAttribute('src'), false);
image.dispatchEvent(event('load'));
studio.draw(canvas);
assert.equal(pictures.length, 2, 'stale media cannot return after the program resumes');
const selection = q('[data-break-demo-target]');
selection.value = selection.options[1].value;
q('[data-break-demo]').checked = true;
q('[data-break-save]').click();
const saved = JSON.parse(window.localStorage.getItem('lightek:holding-break:v1:1:2'));
assert.equal(saved.demoTarget, 'https://demo.example.test/request-agency-demo');
selection.selectedIndex = 0;
const demo = window.LightekBreakDemo.boot(q('[data-holding-break]'));
demo.restore(saved.demo, saved.demoTarget);
demo.draw(canvas);
assert.deepEqual(lines.slice(-2), ['Request an agency demo', 'demo.example.test/request-agency-demo']);
window.close();
console.log('STUDIO_HOLDING_BREAK_PASS customer slate, settings, spot order, isolated audio, and stop');
