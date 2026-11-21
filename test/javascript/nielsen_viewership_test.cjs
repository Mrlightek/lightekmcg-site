const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const { test } = require("node:test");

class Control {
  constructor() { this.listeners = {}; }
  addEventListener(name, fn) { this.listeners[name] = fn; }
  removeEventListener(name) { delete this.listeners[name]; }
  fire(name) { this.listeners[name]?.(); }
}

test("the browser DCR adapter uses the rendered HLS clock and stops on opt-out", async () => {
  const consent = new Control();
  consent.dataset = { nielsenApp: "fixture", nielsenDebug: "true", nielsenTimeline: "/timeline" };
  const player = new Control();
  Object.assign(player, { paused: false, ended: false, seeking: false, readyState: 3 });
  const window = new Control();
  let inits = 0;
  const events = [];
  window.NOLBUNDLE = { nlsQ: () => { inits++; return { trackEvent: event => events.push(event) }; } };
  const content = { assetid: "SHOW1" };
  const timeline = [
    { from: 1700000000, to: 1700000002, content },
    { from: 1700000002, to: 1700000004, content, ad: { assetid: "AD1" } },
    { from: 1700000004, to: 1700000006, content }
  ];
  let current = 1700000001;
  let timer;
  const context = vm.createContext({
    window, navigator: {}, localStorage: { getItem: () => null, setItem: () => {} },
    document: { querySelector: () => consent },
    fetch: async () => ({ ok: true, json: async () => ({ timeline }) }),
    setInterval: callback => { timer = callback; return 1; },
    clearInterval: () => { timer = null; }
  });
  vm.runInContext(fs.readFileSync("public/lightek/live/nielsen-viewership.js", "utf8"), context);
  window.LightekNielsenPlayback(player, () => current);
  player.fire("playing");
  assert.equal(inits, 0);
  assert.equal(timer, undefined);

  consent.checked = true;
  consent.fire("change");
  await new Promise(resolve => setImmediate(resolve));
  timer();
  timer();
  assert.equal(inits, 1);
  assert.equal(events.length, 1);
  assert.equal(events[0].playheadPosition, "1700000001");

  current = 1700000002;
  timer();
  assert.equal(events[1].type, "ad");
  current = 1700000004;
  timer();
  assert.equal(events[2].event, "adStop");
  assert.equal(events[3].type, "content");

  consent.checked = false;
  consent.fire("change");
  assert.equal(timer, null);
  assert.equal(events.length, 4);
});
