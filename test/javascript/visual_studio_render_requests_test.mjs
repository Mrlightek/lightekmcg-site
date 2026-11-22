import assert from "node:assert/strict";
import test from "node:test";
import { RenderRequests } from "../../public/lightek/visual-studio/render-requests.js";

const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

function client(request) {
  const timers = new Map();
  const accepted = [];
  let scheduled = 0;
  let ids = 0;
  const render = new RenderRequests({
    request, historyUrl: "/renders",
    setTimer: (callback, delay) => { timers.set(++scheduled, { callback, delay }); return scheduled; },
    clearTimer: timer => timers.delete(timer),
    stateChanged: () => {},
    historyChanged: () => {},
    accepted: item => accepted.push(item),
    requestId: () => "request-" + ++ids
  });
  return { render, timers, accepted };
}

test("an old history response and a rapid second click cannot unlock submission during autosave or POST", async () => {
  const history = deferred();
  const saved = deferred();
  const response = deferred();
  const sent = [];
  const { render } = client((_url, options) => {
    if (options.method === "POST") { sent.push(options.body); return response.promise; }
    return history.promise;
  });
  const polling = render.refresh();
  const first = render.submit("/renders", () => saved.promise);
  history.resolve([]);
  await polling;
  assert.equal(render.locked, true);
  await render.submit("/renders", () => assert.fail("second click prepared a submission"));
  saved.resolve({ lock_version: 7 });
  await Promise.resolve();
  assert.deepEqual(sent, [{ request_id: "request-1", lock_version: 7 }]);
  await render.submit("/renders", () => assert.fail("second click sent another POST"));
  response.resolve({ id: 1, status: "queued" });
  await first;
  assert.equal(sent.length, 1);
});

test("ignores out-of-order history and keeps polling an active render after a transient failure", async () => {
  const older = deferred();
  const newer = deferred();
  const queued = { id: 1, status: "queued" };
  let call = 0;
  const { render, timers } = client(async () => {
    switch (++call) {
      case 1: return older.promise;
      case 2: return newer.promise;
      case 3: throw Object.assign(new Error("unavailable"), { status: 503 });
      case 4: throw Object.assign(new Error("unavailable"), { status: 503 });
      default: return [{ ...queued, status: "completed" }];
    }
  });
  const first = render.refresh();
  const second = render.refresh();
  newer.resolve([queued]);
  await second;
  older.resolve([]);
  await first;
  assert.equal(render.locked, true);
  await [...timers.values()][0].callback();
  assert.equal(render.locked, true);
  assert.match(render.statusError, /Reconnecting/);
  assert.equal([...timers.values()][0].delay, 2200);
  await [...timers.values()][0].callback();
  assert.equal([...timers.values()][0].delay, 4400);
  await [...timers.values()][0].callback();
  assert.equal(render.locked, false);
  assert.equal(render.statusError, null);
  assert.equal(timers.size, 0);
});

test("a lost POST response keeps the request ID and retry targets the original render", async () => {
  const sent = [];
  const { render, accepted } = client(async (url, options) => {
    if (options.method !== "POST") return [];
    sent.push([url, options.body]);
    if (sent.length === 1) throw new TypeError("connection lost");
    return { id: 2, status: "completed" };
  });
  await assert.rejects(render.submit("/renders/1/retry", () => ({})), /connection lost/);
  await render.submit("/renders/1/retry", () => ({}));
  assert.deepEqual(sent, [
    ["/renders/1/retry", { request_id: "request-1" }],
    ["/renders/1/retry", { request_id: "request-1" }]
  ]);
  assert.equal(accepted[0].id, 2);
});
