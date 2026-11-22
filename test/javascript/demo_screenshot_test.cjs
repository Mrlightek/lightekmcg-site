const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { test } = require('node:test');

const code = fs.readFileSync('public/lightek/demo-screenshot.js', 'utf8');

function browser(surface) {
  const input = {};
  const status = {};
  const button = { hidden: true, addEventListener(_name, activate) { this.activate = activate; } };
  const controls = {
    '[data-capture-start]': button, '[data-capture-file]': input, '[data-capture-status]': status
  };
  const canvas = {
    getContext: () => ({ drawImage() {} }),
    toBlob: callback => callback(new Blob(['captured-frame'], { type: 'image/png' }))
  };
  let stopped = false;
  const track = { stop() { stopped = true; }, getSettings: () => ({ displaySurface: surface }) };
  const stream = { getTracks: () => [track], getVideoTracks: () => [track] };
  class DataTransfer {
    files = [];
    items = { add: file => this.files.push(file) };
  }
  const document = {
    readyState: 'complete', addEventListener() {},
    createElement: tag => tag === 'canvas' ? canvas : { videoWidth: 2560, videoHeight: 1440, play: async () => {} },
    querySelectorAll: () => [{ querySelector: selector => controls[selector] }]
  };
  vm.runInNewContext(code, { document, navigator: { mediaDevices: { getDisplayMedia: async () => stream } }, DataTransfer, File });
  return { button, input, status, canvas, stopped: () => stopped };
}

test('captures one bounded PNG into the review form and releases the browser capture', async () => {
  const view = browser('window');
  assert.equal(view.button.hidden, false);
  await view.button.activate();
  assert.equal(view.input.files[0].type, 'image/png');
  assert.equal(view.canvas.width, 1600);
  assert.equal(view.canvas.height, 900);
  assert.equal(view.stopped(), true);
  assert.match(view.status.textContent, /Save it to review/);
});

test('rejects full-screen capture and releases the browser capture', async () => {
  const view = browser('monitor');
  await view.button.activate();
  assert.equal(view.input.files, undefined);
  assert.equal(view.stopped(), true);
  assert.match(view.status.textContent, /instead of the entire screen/);
});
