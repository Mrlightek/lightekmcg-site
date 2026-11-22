import assert from "node:assert/strict";
import test from "node:test";
import {
  SceneStore, compile, countFrames, cueFrame, depth, frameToCue, frameToKey,
  frameToTime, interpolate, makeLayer, mouthAt, putKey
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
