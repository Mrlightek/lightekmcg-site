import { button, element, label, number, select } from "./dom.js";
import { CURVES, VISEMES, clamp, countFrames, cueEdgeAtFrame, cueFrame, cueFrameSpan, editCueInterval, encodedDurationMs, frameToKey, shiftCueByFrames, timeToFrame } from "./scene-state.js";

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
        const width = Number.isFinite(this.audioDuration) ? Math.min(100, this.audioDuration * 100_000 / encodedDurationMs(spec)) : 100;
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
      if (!channel.mouth) continue;
      const empty = [];
      rows.push(this.row("Mouth · " + name, index, rail => {
        channel.mouth.cues.forEach(cue => {
          const { first, after, count } = cueFrameSpan(cue, spec);
          const timing = `${cue.viseme} · ${cue.start_ms}–${cue.end_ms} ms`;
          const pickCue = () => this.pick(index, "cue", cue);
          if (!count) {
            empty.push(button(timing, pickCue, { class: "vs-cue-empty", "aria-label": `${timing} · No rendered frames` }));
            return;
          }
          const description = `${timing} · frames ${first}–${after - 1}`;
          const block = this.marker(rail, first, button(cue.viseme, pickCue,
            { title: description, "aria-label": description, class: "vs-cue" }));
          block.style.width = this.percent(count + 1) + "%";
          this.drag(block, rail, (delta, edge) => {
            if (edge) this.trimCue(index, cue, edge === "start" ? "start_ms" : "end_ms", (edge === "start" ? first : after) + delta);
            else this.moveCue(index, cue, shiftCueByFrames(cue, delta, spec));
          }, true);
        });
      }));
      if (empty.length) rows.push(element("div", { class: "vs-track" },
        element("span", {}, "No rendered frames"), element("div", { class: "vs-cue-warnings" }, ...empty)));
    }
    this.tracks.replaceChildren(...rows);
    this.updateEditor();
    this.frame();
  }

  row(name, index, fill) {
    const rail = element("div", { class: "vs-rail", onclick: event => {
      if (event.target.closest("button")) return;
      const bounds = rail.getBoundingClientRect();
      this.actions.seek(1 + Math.floor((event.clientX - bounds.left) / bounds.width * this.total));
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

  trimCue(index, cue, edge, frame) {
    const cues = this.channel(index).mouth.cues;
    const time = cueEdgeAtFrame(cue, edge, frame, cues, this.store.spec);
    this.moveCue(index, cue, { [edge]: time });
  }

  moveCue(index, cue, changes) {
    const cues = this.channel(index).mouth.cues;
    const interval = editCueInterval(cue, changes, cues, this.store.spec.duration_ms);
    if (interval.start_ms === cue.start_ms && interval.end_ms === cue.end_ms) return;
    this.actions.edit(() => {
      Object.assign(cue, interval);
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
    const run = callback => next => this.actions.attempt(() => {
      try { callback(next); }
      catch (error) { this.updateEditor(); throw error; }
    });
    if (type === "key") this.editor.append(
      label("Keyframe", number(timeToFrame(item.time_ms, fps), run(frame => this.moveKey(index, item, frame)), { min: 1, max: this.total, step: 1 })),
      label("Incoming curve", select(CURVES.map(curve => [curve, curve]), item.interpolation ?? "LINEAR",
        interpolation => this.actions.edit(() => { item.interpolation = interpolation; }))));
    else {
      const { first, after, count } = cueFrameSpan(item, this.store.spec);
      this.editor.append(
        label("Viseme", select(VISEMES.map(shape => [shape, shape]), item.viseme,
          viseme => this.actions.edit(() => { item.viseme = viseme; }))),
        label("Start (ms)", number(item.start_ms, run(time => this.moveCue(index, item, { start_ms: time })),
          { min: 0, max: item.end_ms - 1, step: 1 })),
        label("End (ms, exclusive)", number(item.end_ms, run(time => this.moveCue(index, item, { end_ms: time })),
          { min: item.start_ms + 1, max: this.store.spec.duration_ms, step: 1 }))
      );
      if (count) this.editor.append(
        label("Start frame", number(first, run(frame => this.trimCue(index, item, "start_ms", frame)),
          { min: 1, max: this.total, step: 1 })),
        label("End frame (inclusive)", number(after - 1, run(frame => this.trimCue(index, item, "end_ms", frame + 1)),
          { min: 1, max: this.total, step: 1 }))
      );
      else this.editor.append(element("p", { class: "vs-message", role: "status" },
        "No rendered frames. Move or extend this cue to cover a frame."));
    }
    this.editor.append(button(type === "key" ? "Delete keyframe" : "Delete cue",
      () => this.actions.edit(() => { list.splice(list.indexOf(item), 1); this.picked = null; })));
  }
}
