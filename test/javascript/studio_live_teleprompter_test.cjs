const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const { JSDOM } = require('jsdom');

test('host can scroll, freestyle, and return to the exact spot without changing cues', () => {
  const dom = new JSDOM(`<main data-live-studio>
    <section data-host-cues>
      <div data-host-script tabindex="0">
        <article data-host-cue>Opening lines</article><article data-host-cue>Closing lines</article>
      </div>
      <p data-host-freestyle-message hidden></p>
      <div data-host-navigation hidden>
        <button data-host-play></button><button data-host-previous></button>
        <button data-host-next></button><button data-host-freestyle></button>
        <span data-host-position></span>
        <input type="range" data-host-speed min="10" max="120" value="40">
        <input type="range" data-host-text-size min="20" max="54" value="30">
      </div>
    </section>
  </main>`, { runScripts: 'outside-only', pretendToBeVisual: true });
  const { window } = dom;
  const pending = new Map();
  let id = 0;
  let time = 0;
  window.requestAnimationFrame = callback => {
    pending.set(++id, callback);
    return id;
  };
  window.cancelAnimationFrame = key => pending.delete(key);
  function tick() {
    time += 100;
    for (const [key, callback] of [...pending]) {
      pending.delete(key);
      callback(time);
    }
  }
  window.eval(readFileSync('public/lightek/live/host-cues.js', 'utf8'));
  window.document.dispatchEvent(new window.Event('DOMContentLoaded'));
  const find = name => window.document.querySelector(`[data-host-${name}]`);
  const script = find('script');
  Object.defineProperties(script, { scrollHeight: { value: 200 }, clientHeight: { value: 100 } });

  assert.equal(pending.size, 0);
  find('play').click();
  tick();
  tick();
  assert.equal(script.scrollTop, 4);
  find('speed').value = '80';
  tick();
  assert.equal(script.scrollTop, 12);
  find('freestyle').click();
  assert.equal(pending.size, 0);
  assert.equal(script.hasAttribute('inert'), true);
  assert.equal(find('freestyle-message').hidden, false);
  find('freestyle').click();
  assert.equal(script.scrollTop, 12);
  assert.equal(pending.size, 0);
  assert.equal(find('position').textContent, 'Cue 1 of 2');

  find('play').click();
  tick();
  tick();
  assert.equal(script.scrollTop, 20);
  script.dispatchEvent(new window.WheelEvent('wheel'));
  assert.equal(pending.size, 0);

  const size = find('text-size');
  size.value = '42';
  size.dispatchEvent(new window.Event('input'));
  assert.equal(script.style.getPropertyValue('--ll-teleprompter-size'), '42px');
  find('next').click();
  assert.equal(script.scrollTop, 0);
  assert.equal(find('position').textContent, 'Cue 2 of 2');
  find('play').click();
  for (let frame = 0; frame < 20; frame++) tick();
  assert.equal(pending.size, 0);
  assert.equal(find('play').textContent, 'Play scroll');
  assert.equal(find('position').textContent, 'Cue 2 of 2');
  dom.window.close();
});
