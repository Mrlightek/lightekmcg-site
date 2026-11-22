import { button, element, label, number, select } from "./dom.js";
import { CURVES, VISEMES, clamp, countFrames, cueFrame, frameToCue, frameToKey, timeToFrame } from "./scene-state.js";

export class Timeline {
  constructor(root, store, actions) {
    Object.assign(this, { root, store, actions });
    this.tracks = root.querySelector("[data-tracks]");
    this.slider = root.querySelector("[data-scrub]");
    this.slider.addEventListener("input", () => actions.seek(Number(this.slider.value)));
    this.editor = element("div", { class: "vs-cue-editor" });
    this.tracks.after(this.editor);
  }

  refresh(assets) {
    const spec = this.store.spec;
    this.total = countFrames(spec);
    this.slider.max = this.total;
    const channels = [["camera", spec.camera, "Camera"], ...spec.layers.map((layer, index) =>
      [index, layer, assets.get(layer.asset_id)?.name ?? "Missing asset"])];
    const rows = [this.row("Audio", undefined, rail => {
      const asset = assets.get(spec.audio_asset_id);
      if (asset) {
        const width = Number.isFinite(this.audioDuration) ? Math.min(100, this.audioDuration * 100_000 / spec.duration_ms) : 100;
        rail.append(element("span", { class: "vs-audio-clip", style: `width:${width}%` }, asset.name));
      }
    })];
    for (const [index, channel, name] of channels) {
      rows.push(this.row(name, index, rail => {
        channel.keyframes.forEach(key => {
          const frame = clamp(timeToFrame(key.time_ms, spec.fps), 1, this.total);
          const mark = this.marker(rail, frame, button("◆", () => this.pick(index, "key", key),
            { title: "Keyframe " + frame, "aria-label": "Keyframe " + frame, class: "vs-key" }));
          this.drag(mark, rail, delta => this.moveKey(index, key, frame + delta));
        });
      }));
      if (channel.mouth) rows.push(this.row("Mouth · " + name, index, rail => {
        channel.mouth.cues.forEach(cue => {
          const first = cueFrame(cue.start_ms, spec.fps);
          const after = cueFrame(cue.end_ms, spec.fps);
          const block = this.marker(rail, first, button(cue.viseme, () => this.pick(index, "cue", cue),
            { title: `${cue.viseme} · frames ${first}–${after - 1}`, class: "vs-cue" }));
          block.style.width = Math.max(100 / this.total, this.percent(after - first + 1)) + "%";
          this.drag(block, rail, (delta, edge) => this.moveCue(index, cue,
            first + (edge === "end" ? 0 : delta), after + (edge === "start" ? 0 : delta)), true);
        });
      }));
    }
    this.tracks.replaceChildren(...rows);
    this.updateEditor();
    this.frame();
  }

  row(name, index, fill) {
    const rail = element("div", { class: "vs-rail", onclick: event => {
      if (event.target.closest("button")) return;
      const bounds = rail.getBoundingClientRect();
      this.actions.seek(1 + Math.round((event.clientX - bounds.left) / bounds.width * (this.total - 1)));
      if (index !== undefined) this.actions.select(index);
    } });
    fill(rail);
    const caption = index === undefined ? element("span", {}, name) :
      button(name, () => this.actions.select(index), { "aria-pressed": index === this.store.selected ? "true" : "false" });
    return element("div", { class: "vs-track" }, caption, rail);
  }

  frame() {
    this.slider.value = this.store.frame;
    this.tracks.style.setProperty("--playhead", this.percent(this.store.frame) + "%");
  }

  percent(frame) { return 100 * (frame - 1) / Math.max(1, this.total); }

  marker(rail, frame, item) {
    item.style.left = this.percent(frame) + "%";
    rail.append(item);
    return item;
  }

  drag(item, rail, apply, trim = false) {
    item.addEventListener("pointerdown", event => {
      if (event.button !== 0) return;
      const left = item.getBoundingClientRect().left;
      const width = item.getBoundingClientRect().width;
      const edge = trim && width > 16 ? event.clientX - left < 6 ? "start" : left + width - event.clientX < 6 ? "end" : null : null;
      const start = event.clientX;
      const originalLeft = item.style.left;
      const originalWidth = item.style.width;
      let delta = 0;
      item.setPointerCapture(event.pointerId);
      const move = next => {
        delta = Math.round((next.clientX - start) * this.total / rail.clientWidth);
        const offset = delta * 100 / this.total;
        if (edge !== "end") item.style.left = `calc(${originalLeft} + ${offset}%)`;
        if (edge) item.style.width = `calc(${originalWidth} + ${edge === "end" ? offset : -offset}%)`;
      };
      const up = end => {
        item.removeEventListener("pointermove", move);
        item.removeEventListener("pointerup", up);
        item.removeEventListener("pointercancel", up);
        item.style.left = originalLeft;
        item.style.width = originalWidth;
        if (!delta || end.type === "pointercancel") return;
        item.addEventListener("click", click => click.stopImmediatePropagation(), { capture: true, once: true });
        this.actions.attempt(() => apply(delta, edge));
      };
      item.addEventListener("pointermove", move);
      item.addEventListener("pointerup", up);
      item.addEventListener("pointercancel", up);
    });
  }

  pick(index, type, item) {
    this.picked = { index, type, item };
    this.actions.select(index);
    this.actions.seek(type === "key" ? timeToFrame(item.time_ms, this.store.spec.fps) : cueFrame(item.start_ms, this.store.spec.fps));
    this.updateEditor();
  }

  channel(index) { return index === "camera" ? this.store.spec.camera : this.store.spec.layers[index]; }

  moveKey(index, key, frame) {
    const channel = this.channel(index);
    const time = Math.min(this.store.spec.duration_ms - 1, frameToKey(clamp(frame, 1, this.total), this.store.spec.fps));
    if (channel.keyframes.some(item => item !== key && item.time_ms === time)) throw new Error("There is already a keyframe at that time.");
    this.actions.edit(() => { key.time_ms = time; channel.keyframes.sort((a, b) => a.time_ms - b.time_ms); });
    this.pick(index, "key", key);
  }

  moveCue(index, cue, first, after) {
    const spec = this.store.spec;
    const start = frameToCue(clamp(first, 1, this.total), spec.fps);
    const end = Math.min(spec.duration_ms, frameToCue(clamp(after, 1, this.total + 1), spec.fps));
    const cues = this.channel(index).mouth.cues;
    if (start >= end || cues.some(item => item !== cue && item.start_ms < end && start < item.end_ms)) {
      throw new Error("Mouth cues must have a duration and cannot overlap on the same layer.");
    }
    this.actions.edit(() => {
      Object.assign(cue, { start_ms: start, end_ms: end });
      cues.sort((a, b) => a.start_ms - b.start_ms);
    });
    this.pick(index, "cue", cue);
  }

  updateEditor() {
    this.editor.replaceChildren();
    const selected = this.picked;
    if (!selected) return;
    const { index, type, item } = selected;
    const channel = this.channel(index);
    const list = type === "key" ? channel?.keyframes : channel?.mouth?.cues;
    if (!list?.includes(item)) return;
    const fps = this.store.spec.fps;
    const run = callback => next => this.actions.attempt(() => callback(next));
    if (type === "key") this.editor.append(
      label("Keyframe", number(timeToFrame(item.time_ms, fps), run(frame => this.moveKey(index, item, frame)), { min: 1, max: this.total, step: 1 })),
      label("Incoming curve", select(CURVES.map(curve => [curve, curve]), item.interpolation ?? "LINEAR",
        interpolation => this.actions.edit(() => { item.interpolation = interpolation; }))));
    else this.editor.append(
      label("Viseme", select(VISEMES.map(shape => [shape, shape]), item.viseme,
        viseme => this.actions.edit(() => { item.viseme = viseme; }))),
      label("Start frame", number(cueFrame(item.start_ms, fps), run(frame => this.moveCue(index, item, frame, cueFrame(item.end_ms, fps))), { min: 1, max: this.total, step: 1 })),
      label("End frame (inclusive)", number(cueFrame(item.end_ms, fps) - 1, run(frame => this.moveCue(index, item, cueFrame(item.start_ms, fps), frame + 1)), { min: 1, max: this.total, step: 1 })));
    this.editor.append(button(type === "key" ? "Delete keyframe" : "Delete cue",
      () => this.actions.edit(() => { list.splice(list.indexOf(item), 1); this.picked = null; })));
  }
}
