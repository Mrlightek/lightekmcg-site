import assert from "node:assert/strict";
import test from "node:test";
import {
  SceneStore, compile, countFrames, cueEdgeAtFrame, cueFrame, cueFrameSpan, depth,
  editCueInterval, encodedDurationMs, frameToCue, frameToKey, frameToTime, interpolate,
  makeLayer, mouthAt, putKey, rhubarbCues, shiftCueByFrames
} from "../../public/lightek/visual-studio/scene-state.js";

test("every authored cue boundary maps to the same Blender frame at 24 and 30 fps", () => {
  for (const fps of [24, 30]) {
    const total = countFrames({ duration_ms: 30_000, fps });
    for (let frame = 1; frame <= total + 1; frame++) {
      assert.equal(cueFrame(frameToCue(frame, fps), fps), frame);
      assert.ok(frameToKey(frame, fps) <= frameToTime(frame, fps));
    }
  }
  const mouth = {
    variants: { X: 1, A: 2 },
    cues: [{ start_ms: 0, end_ms: 41, viseme: "A" }, { start_ms: 41, end_ms: 83, viseme: "B" }]
  };
  assert.deepEqual([1, 2, 3].map(frame => mouthAt(mouth, frame, 24)), ["A", "X", "X"]);
});

test("curves apply to their incoming channel and preserve sparse keys and time-zero overrides", () => {
  const camera = { position: [0, 0, 0], lens: 30, keyframes: [
    { time_ms: 0, position: [2, 0, 0] },
    { time_ms: 100, lens: 40, interpolation: "LINEAR" },
    { time_ms: 1000, position: [10, 0, 0], interpolation: "BEZIER" },
    { time_ms: 2000, position: [0, 0, 0], interpolation: "CONSTANT" }
  ] };
  assert.deepEqual(interpolate(camera, "position", 250), [3.25, 0, 0]);
  assert.deepEqual(interpolate(camera, "position", 1999), [10, 0, 0]);
  assert.deepEqual(interpolate(camera, "position", 2000), [0, 0, 0]);
  assert.equal(interpolate(camera, "lens", 50), 35);
});

test("compiler emits the existing scene document shape without mutating state", () => {
  const asset = { id: 4, dimension_mode: "2_5d", file_url: "/private" };
  const store = new SceneStore({ name: " Scene ", scene_spec: {
    fps: 24, duration_ms: 1000, aspect_ratio: "16:9", layers: [], camera: { keyframes: [] }
  } });
  store.edit(spec => {
    const layer = makeLayer(asset);
    layer.z_depth = 2;
    layer.z_layer = 5;
    putKey(layer, 100, { position: [1, 0, 0] }, "CONSTANT");
    putKey(layer, 100, { scale: [2, 2, 2] });
    layer.mouth = { variants: { A: 2, X: 1 }, cues: [] };
    spec.layers.push(layer);
  });
  const compiled = compile(store);
  assert.equal(compiled.name, "Scene");
  const [layer] = compiled.scene_spec.layers;
  assert.equal(depth(layer), 1.925);
  assert.equal(layer.keyframes[0].interpolation, "CONSTANT");
  assert.deepEqual(Object.keys(layer.mouth.variants), ["X", "A"]);
  assert.deepEqual(Object.keys(store.spec.layers[0].mouth.variants), ["A", "X"]);
  assert.deepEqual(Object.keys(compiled), ["name", "scene_spec"]);
  assert.equal(layer.file_url, undefined);
});

test("tail cues report zero rendered frames while the playhead retains start and end clamping", () => {
  const imported = rhubarbCues({ mouthCues: [{ start: 1.005, end: 1.020, value: "A" }] }, 1020);
  for (const [fps, total] of [[24, 25], [30, 31]]) {
    const spec = { fps, duration_ms: 1020, layers: [] };
    const store = new SceneStore({ name: "Clip", scene_spec: spec });
    store.seek(0);
    assert.equal(store.time, 0);
    store.seek(total + 10);
    assert.equal(store.frame, total);
    assert.equal(store.time, 1000);
    assert.equal(encodedDurationMs(spec), total * 1000 / fps);
    assert.deepEqual(cueFrameSpan(imported[0], spec), { first: total + 1, after: total + 1, count: 0 });
    assert.deepEqual(cueFrameSpan({ ...imported[0], start_ms: 1000 }, spec),
      { first: total, after: total + 1, count: 1 });
    assert.equal(mouthAt({ cues: imported, variants: { A: 1 } }, total, fps), "X");
  }
  assert.deepEqual(imported, [{ start_ms: 1005, end_ms: 1020, viseme: "A" }]);
  assert.equal(cueFrameSpan({ start_ms: 1, end_ms: 35 }, { duration_ms: 1020, fps: 24 }).count, 0);
});

test("frame trims preserve untouched millisecond edges and honor raw adjacency", () => {
  const spec = { fps: 24, duration_ms: 1020 };
  const first = { start_ms: 0, end_ms: 39 };
  const second = { start_ms: 50, end_ms: 180 };
  const cues = [first, second];
  const boundary = cueEdgeAtFrame(first, "end_ms", 3, cues, spec);
  assert.equal(frameToCue(3, 24), 83);
  assert.equal(boundary, 50);
  Object.assign(first, editCueInterval(first, { end_ms: boundary }, cues, spec.duration_ms));
  assert.equal(cueEdgeAtFrame(second, "start_ms", 3, cues, spec), 50);
  const end = cueEdgeAtFrame(second, "end_ms", 5, cues, spec);
  assert.deepEqual(editCueInterval(second, { end_ms: end }, cues, spec.duration_ms), { start_ms: 50, end_ms: 166 });
  assert.throws(() => editCueInterval(second, { start_ms: 49 }, cues, spec.duration_ms), /overlap/);

  const short = { start_ms: 1, end_ms: 10 };
  const adjacent = { start_ms: 10, end_ms: 20 };
  assert.deepEqual(editCueInterval(adjacent, {}, [short, adjacent], spec.duration_ms), adjacent);
  assert.throws(() => editCueInterval(adjacent, { start_ms: 9 }, [short, adjacent], spec.duration_ms), /overlap/);
});

test("moving a cue shifts both raw edges by the same amount and preserves duration at the clip bounds", () => {
  const spec = { fps: 24, duration_ms: 1020 };
  const cue = { start_ms: 50, end_ms: 180 };
  assert.deepEqual(shiftCueByFrames(cue, 1, spec), { start_ms: 92, end_ms: 222 });
  assert.deepEqual(shiftCueByFrames(cue, -20, spec), { start_ms: 0, end_ms: 130 });
  assert.deepEqual(shiftCueByFrames(cue, 100, spec), { start_ms: 890, end_ms: 1020 });
});
