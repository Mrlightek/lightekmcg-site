export const VISEMES = ["X", "A", "B", "C", "D", "E", "F", "G", "H"];
export const CURVES = ["LINEAR", "BEZIER", "CONSTANT"];
export const identity = { position: [0, 0, 0], rotation: [0, 0, 0], scale: [1, 1, 1] };
const channelFields = ["position", "rotation", "scale", "lens"];
export const countFrames = ({ duration_ms, fps }) => Math.ceil(duration_ms * fps / 1000);
export const encodedDurationMs = spec => 1000 * countFrames(spec) / spec.fps;
export const frameToTime = (frame, fps) => (frame - 1) * 1000 / fps;
export const timeToFrame = (time, fps) => 1 + Math.round(time * fps / 1000);
export const cueFrame = (time, fps) => 1 + Math.ceil(time * fps / 1000);
// Frame boundaries are rounded down for cues. Blender's ceil then lands on
// the intended frame even when a boundary is a fractional millisecond.
export const frameToCue = (frame, fps) => Math.floor(frameToTime(frame, fps));
export const frameToKey = (frame, fps) => Math.floor(frameToTime(frame, fps));
export const clamp = (number, low, high) => Math.min(high, Math.max(low, number));
export const depth = layer => (layer.z_depth ?? 0) - layer.z_layer * 0.015;
export const degrees = angle => angle * Math.PI / 180;
export const aspect = spec => spec.aspect_ratio === "9:16" ? 9 / 16 : 16 / 9;
export const cameraFov = (lens, ratio) => 360 / Math.PI * Math.atan(18 / (lens * Math.max(1, ratio)));

// Blender switches visemes at ceil(time × fps), on 1-based frames. The
// exclusive clip boundary is one past the final rendered frame.
export function cueFrameSpan(cue, spec) {
  const boundary = countFrames(spec) + 1;
  const first = clamp(cueFrame(cue.start_ms, spec.fps), 1, boundary);
  const after = clamp(cueFrame(cue.end_ms, spec.fps), 1, boundary);
  return { first, after, count: Math.max(0, after - first) };
}

export function editCueInterval(cue, changes, cues, duration) {
  const { start_ms, end_ms } = { ...cue, ...changes };
  if (!Number.isInteger(start_ms) || !Number.isInteger(end_ms) ||
      start_ms < 0 || end_ms > duration || start_ms >= end_ms) {
    throw new Error("Mouth cues must have a positive duration and fit within the scene.");
  }
  if (cues.some(item => item !== cue && item.start_ms < end_ms && start_ms < item.end_ms)) {
    throw new Error("Mouth cues cannot overlap on the same layer.");
  }
  return { start_ms, end_ms };
}

export function cueEdgeAtFrame(cue, edge, frame, cues, spec) {
  const first = edge === "start_ms";
  const target = clamp(frame, 1, countFrames(spec) + 1);
  if (cueFrame(cue[edge], spec.fps) === target) return cue[edge];
  const snap = Math.min(frameToCue(target, spec.fps), spec.duration_ms);
  const neighbors = cues.filter(item => item !== cue);
  // A single displayed frame can represent many millisecond edges. A trim
  // into an adjacent cue's frame can meet its actual edge within that frame.
  const bound = first
    ? Math.max(0, ...neighbors.filter(item => item.end_ms <= cue.start_ms).map(item => item.end_ms))
    : Math.min(spec.duration_ms, ...neighbors.filter(item => item.start_ms >= cue.end_ms).map(item => item.start_ms));
  if (cueFrame(bound, spec.fps) === target) return first ? Math.max(snap, bound) : Math.min(snap, bound);
  return snap;
}

export function shiftCueByFrames(cue, delta, spec) {
  const offset = clamp(Math.round(delta * 1000 / spec.fps), -cue.start_ms, spec.duration_ms - cue.end_ms);
  return { start_ms: cue.start_ms + offset, end_ms: cue.end_ms + offset };
}

export function interpolate(channel, field, time) {
  const keys = channel.keyframes.filter(key => key[field] !== undefined);
  let left = { time_ms: 0, [field]: channel[field] };
  for (const right of keys) {
    if (right.time_ms > time) {
      let amount = (time - left.time_ms) / (right.time_ms - left.time_ms);
      if (right.interpolation === "CONSTANT") amount = 0;
      if (right.interpolation === "BEZIER") amount = amount * amount * (3 - 2 * amount);
      const lerp = (a, b) => a + (b - a) * amount;
      return Array.isArray(left[field]) ? left[field].map((value, i) => lerp(value, right[field][i])) : lerp(left[field], right[field]);
    }
    left = right;
  }
  return left[field];
}

export function transformAt(channel, time) {
  return Object.fromEntries(channelFields.filter(field => field in channel).map(field => [field, interpolate(channel, field, time)]));
}

export function mouthAt(mouth, frame, fps) {
  const cue = mouth.cues.find(cue => cueFrame(cue.start_ms, fps) <= frame && frame < cueFrame(cue.end_ms, fps));
  return cue && mouth.variants[cue.viseme] ? cue.viseme : "X";
}

export function rhubarbCues(value, duration) {
  const input = value?.mouthCues;
  if (!Array.isArray(input) || input.length > 600) throw new Error("Choose a Rhubarb JSON file with up to 600 mouth cues.");
  let previous = 0;
  return input.map(item => {
    const start_ms = Math.round(item?.start * 1000);
    const end_ms = Math.round(item?.end * 1000);
    const viseme = item?.value;
    if (!Number.isFinite(start_ms) || !Number.isFinite(end_ms) || start_ms < previous ||
        start_ms >= end_ms || end_ms > duration || !VISEMES.includes(viseme)) {
      throw new Error("Rhubarb cues must be ordered, non-overlapping, and fit within the scene duration.");
    }
    previous = end_ms;
    return { start_ms, end_ms, viseme };
  });
}

export function makeLayer(asset) {
  const mode = asset.dimension_mode;
  return {
    ...structuredClone(identity), asset_id: asset.id, dimension_mode: mode,
    z_layer: 0, keyframes: [], ...(mode === "2_5d" ? { z_depth: 0, relief: 0 } : {})
  };
}

export function putKey(channel, time, values, interpolation) {
  const current = channel.keyframes.find(key => key.time_ms === time);
  if (!current && channel.keyframes.length >= 120) throw new Error("This track already has 120 keyframes.");
  const key = { ...current, ...values, time_ms: time, interpolation: interpolation ?? current?.interpolation ?? "LINEAR" };
  channel.keyframes = [...channel.keyframes.filter(item => item !== current), key].sort(byTime);
  return key;
}

const byTime = (a, b) => a.time_ms - b.time_ms;
const byCue = (a, b) => a.start_ms - b.start_ms;

// The editor retains the Rails scene_spec as its document. Asset URLs, layer
// selection, playhead and worker receipts live outside the document.
export function compile(state) {
  const spec = structuredClone(state.spec);
  for (const channel of [spec.camera, ...spec.layers]) {
    channel.keyframes.sort(byTime);
    if (channel.mouth) {
      channel.mouth.cues.sort(byCue);
      channel.mouth.variants = Object.fromEntries(VISEMES.filter(shape => channel.mouth.variants[shape])
        .map(shape => [shape, channel.mouth.variants[shape]]));
    }
  }
  return { name: state.name.trim(), scene_spec: spec };
}

export class SceneStore {
  constructor(document) {
    this.name = document.name;
    this.spec = structuredClone(document.scene_spec);
    this.revision = 0;
    this.saved = 0;
    this.selected = this.spec.layers.length ? 0 : "camera";
    this.frame = 1;
  }

  get channel() { return this.selected === "camera" ? this.spec.camera : this.spec.layers[this.selected]; }
  get time() { return frameToTime(this.frame, this.spec.fps); }
  get dirty() { return this.revision !== this.saved; }

  edit(change) {
    change(this.spec);
    this.revision++;
  }

  seek(frame) {
    this.frame = clamp(Math.round(frame), 1, countFrames(this.spec));
  }
}
