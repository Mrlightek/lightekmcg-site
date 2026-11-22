import { assetDrawer, assetForm } from "./asset-drawer.js";
import { button, element } from "./dom.js";
import { inspector } from "./inspector.js";
import { SceneStore, clamp, compile, countFrames, frameToCue, frameToKey, makeLayer, putKey, rhubarbCues, timeToFrame, transformAt } from "./scene-state.js";
import { Timeline } from "./timeline.js";
import { Viewport } from "./viewport.js";

const root = document.querySelector("#visual-studio");
const get = name => root.querySelector("[data-" + name + "]");
const urls = root.dataset;
const errorMessage = message => { get("message").textContent = message; };
const csrf = document.querySelector('meta[name="csrf-token"]')?.content;

async function request(url, { method = "GET", body } = {}) {
  const multipart = body instanceof FormData;
  const headers = { Accept: "application/json" };
  if (method !== "GET") headers["X-CSRF-Token"] = csrf ?? "";
  if (body && !multipart) headers["Content-Type"] = "application/json";
  const response = await fetch(url, { method, headers, body: body && (multipart ? body : JSON.stringify(body)) });
  if (response.status === 204) return null;
  const data = await response.json().catch(() => null);
  if (!response.ok || !data) throw new Error(data?.error ?? "Studio could not complete the request (" + response.status + ").");
  return data;
}

function member(url, id) {
  const result = new URL(url, location.href);
  result.pathname += "/" + id;
  return result.href;
}

function attempt(callback) {
  return Promise.resolve().then(callback).catch(error => { errorMessage(error.message); return false; });
}

async function boot() {
  const [scene, library] = await Promise.all([request(urls.sceneUrl), request(urls.assetsUrl)]);
  const store = new SceneStore(scene);
  let lockVersion = scene.lock_version;
  const assets = new Map(library.map(item => [item.id, item]));
  const sound = new Audio();
  sound.preload = "metadata";
  let audioUrl;
  let loop = null;
  let playing = false;
  let playStart;
  let startMs;
  let usingAudio = false;
  let saving;
  let saveTimer;
  let renderTimer;

  function previewNotice(text) {
    const notice = get("preview-message");
    if (notice.textContent !== text) notice.textContent = text;
  }

  const viewport = new Viewport(get("stage"), store, {
    notice: previewNotice,
    select,
    move: position => {
      changeTransform("position", position.map(value => clamp(value, -3600, 3600)), false);
      viewport.draw();
    },
    finish: () => { refresh(); scheduleSave(); },
    zoom: direction => {
      const camera = transformAt(store.spec.camera, store.time);
      select("camera");
      changeTransform("lens", clamp(camera.lens * (direction > 0 ? 0.9 : 1.1), 12, 100));
    },
    loaded: () => drawInspector()
  });
  const timeline = new Timeline(root, store, { attempt, edit, seek, select });
  sound.addEventListener("loadedmetadata", () => {
    timeline.audioDuration = sound.duration;
    timeline.refresh(assets);
  });

  function transformChange(channel, field, value) {
    if (value === undefined) return;
    const time = Math.min(store.spec.duration_ms - 1, frameToKey(store.frame, store.spec.fps));
    const nearest = channel.keyframes.find(key => timeToFrame(key.time_ms, store.spec.fps) === store.frame && field in key);
    if (store.frame === 1 && !channel.keyframes.some(key => field in key)) channel[field] = value;
    else putKey(channel, nearest?.time_ms ?? time, { [field]: value });
  }

  function changeTransform(field, value, update = true) {
    const change = () => transformChange(store.channel, field, value);
    if (update) attempt(() => edit(change));
    else {
      try { store.edit(change); } catch (error) { errorMessage(error.message); }
    }
  }

  function drawInspector() {
    const clips = viewport.entries[store.selected]?.clips.map(clip => clip.name) ?? [];
    inspector(get("inspector"), store, assets, {
      transform: changeTransform, layer: change => edit(() => change(store.channel)),
      remove: () => edit(spec => { spec.layers.splice(store.selected, 1); store.selected = "camera"; timeline.picked = null; })
    }, clips);
  }

  function select(selection) {
    store.selected = selection;
    drawInspector();
    timeline.refresh(assets);
    paint();
  }

  function refresh() {
    store.seek(store.frame);
    const spec = store.spec;
    get("format").value = spec.aspect_ratio;
    get("fps").value = spec.fps;
    get("duration").value = spec.duration_ms / 1000;
    const url = assets.get(spec.audio_asset_id)?.file_url;
    if (audioUrl !== url) {
      pause();
      audioUrl = url;
      timeline.audioDuration = null;
      if (url) sound.src = url;
      else { sound.removeAttribute("src"); sound.load(); }
    }
    viewport.sync(assets);
    drawInspector();
    timeline.refresh(assets);
    paint();
  }

  function paint() {
    get("frame").textContent = `Frame ${store.frame} / ${countFrames(store.spec)}`;
    get("time").textContent = (store.time / 1000).toFixed(3) + " s";
    get("add-cue").disabled = get("import-cues").disabled = !store.channel.mouth;
    timeline.frame();
    viewport.draw();
  }

  function seek(frame) {
    pause();
    store.seek(frame);
    if (audioUrl && Number.isFinite(sound.duration)) sound.currentTime = Math.min(store.time / 1000, sound.duration);
    drawInspector();
    paint();
  }

  function pause() {
    if (loop !== null) cancelAnimationFrame(loop);
    loop = null;
    playing = false;
    sound.pause();
    get("play").textContent = "Play";
  }

  function advance(now) {
    if (!playing) return;
    let elapsed = startMs + now - playStart;
    if (usingAudio) {
      elapsed = sound.currentTime * 1000;
      if (sound.ended) {
        usingAudio = false;
        playStart = now;
        startMs = elapsed;
      }
    }
    if (elapsed >= store.spec.duration_ms) {
      seek(countFrames(store.spec));
      return;
    }
    store.seek(1 + Math.floor(elapsed * store.spec.fps / 1000 + 1e-7));
    paint();
    loop = requestAnimationFrame(advance);
  }

  async function play() {
    if (playing) { pause(); drawInspector(); return; }
    if (store.frame === countFrames(store.spec)) seek(1);
    startMs = store.time;
    playStart = performance.now();
    usingAudio = !!audioUrl && (!Number.isFinite(sound.duration) || startMs < sound.duration * 1000);
    playing = true;
    get("play").textContent = "Pause";
    if (usingAudio) {
      try {
        sound.currentTime = startMs / 1000;
        await sound.play();
      } catch {
        usingAudio = false;
        playStart = performance.now();
        errorMessage("Audio preview is unavailable. Timeline playback will continue.");
      }
    }
    if (playing) loop = requestAnimationFrame(advance);
  }

  function edit(change) {
    pause();
    store.edit(change);
    refresh();
    scheduleSave();
  }

  function scheduleSave() {
    get("save-status").textContent = "Unsaved changes";
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => attempt(save), 650);
  }

  function save() {
    clearTimeout(saveTimer);
    if (saving) return saving;
    saving = (async () => {
      while (store.dirty) {
        const revision = store.revision;
        const payload = compile(store);
        if (!payload.name) throw new Error("Enter a scene name before saving.");
        payload.lock_version = lockVersion;
        get("save-status").textContent = "Saving…";
        const result = await request(urls.sceneUrl, { method: "PATCH", body: { scene: payload } });
        lockVersion = result.lock_version;
        store.saved = revision;
      }
      get("save-status").textContent = "Saved";
    })().catch(error => {
      get("save-status").textContent = "Unsaved changes";
      throw error;
    }).finally(() => { saving = undefined; });
    return saving;
  }

  function addKey() {
    let key;
    edit(spec => {
      const time = Math.min(spec.duration_ms - 1, frameToKey(store.frame, spec.fps));
      const current = transformAt(store.channel, store.time);
      key = putKey(store.channel, time, current);
    });
    timeline.pick(store.selected, "key", key);
  }

  function addCue() {
    const { spec, channel, frame } = store;
    if (!channel.mouth) throw new Error("Choose a rest mouth image in the Inspector.");
    if (channel.mouth.cues.length >= 600) throw new Error("This layer already has 600 mouth cues.");
    const cues = channel.mouth.cues;
    const start = frameToCue(frame, spec.fps);
    const next = cues.find(cue => cue.start_ms >= start);
    const end = Math.min(spec.duration_ms, next?.start_ms ?? Infinity, frameToCue(frame + 3, spec.fps));
    if (start >= end || cues.some(cue => cue.start_ms <= start && start < cue.end_ms))
      throw new Error("Move the playhead to an empty part of this mouth track.");
    const viseme = Object.keys(channel.mouth.variants).find(shape => shape !== "X") ?? "X";
    const cue = { start_ms: start, end_ms: end, viseme };
    edit(() => { cues.push(cue); cues.sort((a, b) => a.start_ms - b.start_ms); });
    timeline.pick(store.selected, "cue", cue);
  }

  const assetActions = {
    add: asset => attempt(() => edit(spec => {
      if (spec.layers.length >= 24) throw new Error("A scene can have up to 24 layers.");
      spec.layers.push(makeLayer(asset));
      store.selected = spec.layers.length - 1;
    })),
    audio: id => edit(spec => { spec.audio_asset_id = id; updateDrawer(); }),
    manage: asset => {
      const dialog = element("dialog", { class: "vs-panel" }, element("h2", {}, asset.name), assetForm(asset, assetActions));
      dialog.append(button("Close", () => dialog.close()));
      root.append(dialog);
      dialog.addEventListener("close", () => dialog.remove(), { once: true });
      dialog.showModal();
    },
    saveAsset: (asset, fields) => attempt(async () => {
      const item = await request(asset ? member(urls.assetsUrl, asset.id) : urls.assetsUrl,
        { method: asset ? "PATCH" : "POST", body: fields });
      assets.set(item.id, item);
      updateDrawer();
      refresh();
      return item;
    }),
    deleteAsset: asset => attempt(async () => {
      const spec = store.spec;
      if (spec.audio_asset_id === asset.id || spec.layers.some(layer => layer.asset_id === asset.id || Object.values(layer.mouth?.variants ?? {}).includes(asset.id)))
        throw new Error("Remove this asset from the current scene before deleting it.");
      if (!confirm("Delete " + asset.name + " from your library?")) return;
      await request(member(urls.assetsUrl, asset.id), { method: "DELETE" });
      assets.delete(asset.id);
      root.querySelector("dialog[open]")?.close();
      updateDrawer();
      refresh();
    }),
    preview: asset => attempt(async () => {
      const item = await request(asset.preview_request_url, { method: "POST" });
      assets.set(item.id, item);
      updateDrawer();
      pollPreview(item.id);
    })
  };

  function updateDrawer() {
    assetDrawer(get("library"), assets, assetActions);
    if (store.spec.audio_asset_id) get("library").append(button("Remove scene audio", () => edit(spec => { delete spec.audio_asset_id; updateDrawer(); })));
  }

  const previewPolls = new Map();
  function pollPreview(id) {
    if (previewPolls.has(id)) return;
    const poll = async () => {
      try {
        const item = await request(member(urls.assetsUrl, id));
        assets.set(id, item);
        if (item.preview_status === "queued") {
          previewPolls.set(id, setTimeout(poll, 2500));
          return;
        }
        updateDrawer();
        refresh();
        if (item.preview_status === "failed") errorMessage("The model preview failed. Check the model file or try the preview again.");
      } catch (error) {
        errorMessage(error.message);
      }
      previewPolls.delete(id);
    };
    previewPolls.set(id, setTimeout(poll, 2500));
  }

  let selectedRender;
  async function refreshRenders() {
    clearTimeout(renderTimer);
    const items = await request(urls.rendersUrl);
    const active = items.find(item => !["completed", "failed"].includes(item.status));
    get("render-status").textContent = active ? " · " + active.status + " " + active.progress + "%" : "";
    get("render").disabled = !!active;
    get("render-list").replaceChildren(...items.map(item => element("div", { class: "vs-render-row" },
      element("span", {}, `Render ${item.id} · ${item.status}${item.error_message ? " · " + item.error_message : ""}`),
      item.video_url ? button("Watch", () => showVideo(item)) : null)));
    const completed = selectedRender ? items.find(item => item.id === selectedRender && item.video_url) : items.find(item => item.video_url);
    if (completed && get("video").getAttribute("src") !== completed.video_url) showVideo(completed);
    if (active) renderTimer = setTimeout(() => attempt(refreshRenders), 2200);
  }

  function showVideo(item) {
    selectedRender = item.id;
    const video = get("video");
    video.src = item.video_url;
    video.hidden = false;
    const download = get("download");
    download.href = item.download_url;
    download.hidden = false;
  }

  get("name").addEventListener("input", event => {
    store.name = event.target.value;
    store.revision++;
    scheduleSave();
  });
  get("format").addEventListener("change", event => edit(spec => { spec.aspect_ratio = event.target.value; }));
  get("fps").addEventListener("change", event => edit(spec => {
    const time = store.time;
    spec.fps = Number(event.target.value);
    store.seek(timeToFrame(time, spec.fps));
  }));
  get("duration").addEventListener("change", event => {
    const field = event.target;
    const duration = Math.round(field.valueAsNumber * 1000);
    const over = [store.spec.camera, ...store.spec.layers].some(channel =>
      channel.keyframes.some(key => key.time_ms >= duration) || channel.mouth?.cues.some(cue => cue.end_ms > duration));
    if (!field.checkValidity() || !Number.isFinite(duration) || over) {
      errorMessage(over ? "Move or remove keyframes and mouth cues beyond the new end first." : "Choose a duration from 1 to 30 seconds.");
      field.value = store.spec.duration_ms / 1000;
      return;
    }
    edit(spec => { spec.duration_ms = duration; });
  });
  get("camera").addEventListener("click", () => select("camera"));
  get("save").addEventListener("click", () => attempt(save));
  get("play").addEventListener("click", () => attempt(play));
  get("add-key").addEventListener("click", () => attempt(addKey));
  get("add-cue").addEventListener("click", () => attempt(addCue));
  get("import-cues").addEventListener("click", () => get("cue-file").click());
  get("cue-file").addEventListener("change", event => attempt(async () => {
    const field = event.target;
    const file = field.files[0];
    field.value = "";
    if (!file) return;
    if (file.size > 512_000) throw new Error("The Rhubarb cue file must be under 512 KB.");
    const mouth = store.channel.mouth;
    if (!mouth) return;
    const cues = rhubarbCues(JSON.parse(await file.text()), store.spec.duration_ms);
    if (mouth.cues.length && !confirm("Replace the selected layer’s existing mouth cues?")) return;
    edit(() => { mouth.cues = cues; timeline.picked = null; });
  }));
  get("render").addEventListener("click", () => attempt(async () => {
    get("render").disabled = true;
    try {
      while (store.dirty) await save();
      const render = await request(urls.rendersUrl, { method: "POST" });
      selectedRender = render.id;
      get("video").removeAttribute("src");
      get("video").hidden = true;
      get("download").hidden = true;
      get("renders").open = true;
      await refreshRenders();
    } catch (error) {
      get("render").disabled = false;
      throw error;
    }
  }));
  get("delete-scene").addEventListener("click", () => attempt(async () => {
    if (!confirm("Delete this scene and its finished exports?")) return;
    clearTimeout(saveTimer);
    if (saving) await saving;
    await request(urls.sceneUrl, { method: "DELETE" });
    store.saved = store.revision;
    location.assign(urls.libraryUrl);
  }));
  window.addEventListener("beforeunload", event => {
    if (store.dirty) { event.preventDefault(); event.returnValue = ""; }
  });
  updateDrawer();
  refresh();
  for (const item of assets.values()) if (item.preview_status === "queued") pollPreview(item.id);
  errorMessage("");
  await refreshRenders();
}

attempt(boot);
