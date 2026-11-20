const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {JSDOM} = require('jsdom');
const {window} = new JSDOM(`<div data-holding-break data-break-brand="Client Studio" data-break-scope="1:2">
  <input value="Client Studio" data-break-brand-input><input value="Back in a moment." data-break-heading>
  <input value="Stay with us." data-break-message>
  <select data-break-item><option value="15" data-kind="image">Ad</option></select>
  <select data-break-item><option value="24" data-kind="video">Commercial</option></select>
  <select data-break-music><option value="19">Music</option></select>
  <input value="0.25" data-break-volume><button data-break-save></button><button data-break-next></button>
  <span data-break-status></span></div>`, {url:'https://studio.test', runScripts:'outside-only'});
const created = [];
const createElement = window.document.createElement.bind(window.document);
window.document.createElement = name => {
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
const canvas = {fillRect() {}, fillText: (...args) => lines.push(args[0]), drawImage: (...args) => pictures.push(args)};
const event = name => new window.Event(name);
window.eval(readFileSync('public/lightek/live/holding-break.js','utf8'));
const q = selector => window.document.querySelector(selector);
const studio = window.LightekHoldingBreak.boot(window.document);
studio.draw(canvas);
assert.deepEqual(lines, ['Client Studio', 'Back in a moment.', 'Stay with us.']);
assert.equal(created.length, 0, 'an automatic hold depicts the slate without starting a paid break');
q('[data-break-heading]').value = 'Sponsor break';
q('[data-break-save]').click();
assert.equal(JSON.parse(window.localStorage.getItem('lightek:holding-break:v1:1:2')).heading, 'Sponsor break');
studio.start(context, {});
const [music, image] = created;
assert.equal(music.getAttribute('src'), '/api/lightek/pwa/assets/19/proxy');
assert.equal(gains[0].gain.value, .25);
image.dispatchEvent(event('load'));
studio.draw(canvas);
assert.equal(pictures[0][0], image);
q('[data-break-next]').click();
const video = created[2];
assert.equal(gains[0].gain.value, 0, 'music is ducked while the commercial is queued');
video.dispatchEvent(event('canplay'));
assert.equal(gains[1].gain.value, 1);
video.dispatchEvent(event('ended'));
studio.draw(canvas);
assert.equal(pictures.length, 1);
assert.equal(gains[1].gain.value, 0);
assert.equal(gains[0].gain.value, .25, 'music returns with the slate');
studio.stop();
assert.equal(gains[0].gain.value, 0);
assert.equal(music.hasAttribute('src'), false);
image.dispatchEvent(event('load'));
studio.draw(canvas);
assert.equal(pictures.length, 1, 'stale media cannot return after the program resumes');
window.close();
console.log('STUDIO_HOLDING_BREAK_PASS customer slate, settings, spot order, isolated audio, and stop');
