import { PipelineViewport } from "./pipeline-viewport.js";

const hub = document.querySelector("#pipeline-hub");
const siteId = hub.dataset.siteId;
const $ = (id) => document.getElementById(id);
const csrf = document.querySelector('meta[name="csrf-token"]').content;
const stages = [
  ["base", "1. Base Mesh", "MakeHuman", "Drop a base mesh"],
  ["mixamo", "2. Rig & Animate", "Mixamo", null],
  ["props", "3. Voxel / Props", "Animatoon / Unity", "Drop an export"],
  ["ready", "4. Scene-Ready", ".glb", null],
  ["rendered", "5. Rendered", ".mp4", null]
];
const statusLabels = {queued: "Queued", processing: "Normalizing", prepared: "Prepared", ready: "Ready",
  failed: "Failed", pending: "Queued", running: "Rendering", completed: "Complete", cancelled: "Cancelled"};
const objects = new Map();
const cards = new Map();
let viewport, preview, selected, uploadContext, searchTimer, syncCount = 0;
let boardSignature, librarySignature, renderSignature, renderPending = false;

function element(tag, text, className) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  if (className) node.className = className;
  return node;
}
function button(text, callback, className) {
  const control = element("button", text, className);
  control.type = "button";
  control.addEventListener("click", callback);
  return control;
}
function link(text, url) {
  const anchor = element("a", text);
  anchor.href = url;
  return anchor;
}
function message(target, text, error = false) {
  target.textContent = text;
  target.classList.toggle("error", error);
}
function notice(text, error = false) { message($("hub-notice"), text, error); }

async function request(endpoint, {method = "GET", body, query = ""} = {}) {
  const headers = {Accept: "application/json"};
  if (method !== "GET") headers["X-CSRF-Token"] = csrf;
  if (body && !(body instanceof FormData)) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }
  const response = await fetch(`/api/v1${endpoint}?site_id=${encodeURIComponent(siteId)}${query}`,
    {method, body, headers, credentials: "same-origin", cache: "no-store"});
  const data = await response.json().catch(() => ({}));
  if (!response.ok || response.redirected) throw new Error(data.error || `Studio request failed (${response.status}). Check your session.`);
  return data;
}

function dropzone(target, onDrop) {
  target.addEventListener("dragover", (event) => {
    if (!event.dataTransfer.types.includes("Files")) return;
    event.preventDefault();
    target.classList.add("drag-over");
  });
  target.addEventListener("dragleave", () => target.classList.remove("drag-over"));
  target.addEventListener("drop", (event) => {
    event.preventDefault();
    target.classList.remove("drag-over");
    if (event.dataTransfer.files.length) onDrop(event.dataTransfer.files);
  });
}

async function sync() {
  const serial = ++syncCount;
  const q = $("asset-search").value.trim();
  try {
    const data = await request("/assets/pipeline", {query: q ? `&q=${encodeURIComponent(q)}` : ""});
    if (serial !== syncCount) return;
    data.cards.concat(data.readyAssets).forEach((card) => cards.set(card.id, card));
    const signatures = [JSON.stringify(data.cards), JSON.stringify(data.readyAssets), JSON.stringify(data.renders)];
    if (signatures[0] !== boardSignature) {
      buildBoard(data.cards);
      boardSignature = signatures[0];
    }
    if (signatures[1] !== librarySignature) {
      buildLibrary(data.readyAssets);
      librarySignature = signatures[1];
    }
    if (signatures[2] !== renderSignature) {
      buildRenders(data.renders);
      renderSignature = signatures[2];
    }
  } catch (error) {
    if (serial === syncCount) notice(error.message, true);
  } finally {
    if (serial === syncCount) $("asset-board").setAttribute("aria-busy", "false");
  }
}

function buildBoard(records) {
  const content = stages.map(([id, title, description, dropLabel]) => {
    const lane = element("section", null, "lane");
    lane.setAttribute("aria-label", title);
    const heading = element("h3", title);
    lane.append(heading, element("p", description));
    if (dropLabel) {
      const target = button(dropLabel, () => openUpload({mode: id}), "lane-upload drop-target");
      dropzone(target, (files) => openUpload({mode: id}, files));
      lane.append(target);
    }
    const items = records.filter((card) => card.stage === id);
    items.forEach((card) => lane.append(assetCard(card)));
    if (!items.length && !dropLabel) {
      const empty = {mixamo: "Prepare a base mesh to start a handoff.", ready: "Normalized models appear here.",
        rendered: "Assets used in completed videos appear here."};
      lane.append(element("p", empty[id]));
    }
    return lane;
  });
  $("asset-board").replaceChildren(...content);
}

function assetCard(card) {
  const item = element("article", null, "pipeline-card");
  item.append(element("strong", card.name), element("small", statusLabels[card.status] || card.status));
  if (card.error) item.append(element("p", card.error, "error"));
  const actions = element("div", null, "card-actions");
  if (card.canPrepare) {
    actions.append(button(card.stage === "mixamo" ? "Download Mixamo FBX" : "Prepare for Mixamo", async (event) => {
      const control = event.currentTarget;
      control.disabled = true;
      try {
        const result = await request(`/assets/pipeline/${card.id}/mixamo`, {method: "POST", body: {}});
        const download = link("Download Mixamo FBX", result.downloadUrl);
        download.download = "mixamo.fbx";
        document.body.append(download);
        download.click();
        download.remove();
        notice("Upload the returned Mixamo FBX on the same card.");
        await sync();
      } catch (error) { notice(error.message, true); }
      finally { control.disabled = false; }
    }));
  }
  if (card.stage === "mixamo" && !["queued", "processing"].includes(card.status)) {
    const context = {mode: "props", assetId: card.id, mixamo: true};
    const target = button("Drop the Mixamo FBX", () => openUpload(context), "drop-target");
    dropzone(target, (files) => openUpload(context, files));
    actions.append(target);
  } else if (card.status === "failed") {
    const context = {mode: card.stage, assetId: card.id, modelPath: card.modelPath};
    const target = button("Replace export", () => openUpload(context), "drop-target");
    dropzone(target, (files) => openUpload(context, files));
    actions.append(target);
  }
  if (card.previewUrl) {
    actions.append(button("3D preview", () => openPreview(card)), button("Add to scene", () => addAsset(card)));
  }
  item.append(actions);
  return item;
}

function openUpload(context, files) {
  uploadContext = context;
  const form = $("upload-form");
  form.reset();
  form.elements.mode.value = context.mode;
  form.elements.mode.disabled = Boolean(context.assetId);
  form.elements.file.accept = context.mixamo ? ".fbx" : ".fbx,.glb,.gltf,.unitypackage";
  form.elements.model_path.value = context.modelPath || "";
  if (files) {
    const transfer = new DataTransfer();
    transfer.items.add(files[0]);
    form.elements.file.files = transfer.files;
  }
  updateUploadFields();
  message($("upload-status"), "");
  if (!$("upload-dialog").open) $("upload-dialog").showModal();
}

function updateUploadFields() {
  const file = $("upload-form").elements.file.files[0];
  const name = file?.name.toLowerCase() || "";
  $("upload-form").querySelectorAll("[data-model-path]").forEach((item) => { item.hidden = !name.endsWith(".unitypackage"); });
  $("upload-form").querySelectorAll("[data-sidecars]").forEach((item) => { item.hidden = !/\.(gltf|fbx)$/.test(name); });
}
$("upload-form").elements.file.addEventListener("change", updateUploadFields);
dropzone($("upload-target"), (files) => {
  const transfer = new DataTransfer();
  transfer.items.add(files[0]);
  $("upload-form").elements.file.files = transfer.files;
  updateUploadFields();
});
$("upload-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const submit = form.querySelector('button[type="submit"]');
  const model = form.elements.file.files[0];
  const body = new FormData();
  body.set("file", model);
  body.set("mode", form.elements.mode.value);
  if (uploadContext?.assetId) body.set("asset_id", uploadContext.assetId);
  if (/\.unitypackage$/i.test(model.name) && form.elements.model_path.value.trim()) {
    body.set("model_path", form.elements.model_path.value.trim());
  }
  if (/\.(fbx|gltf)$/i.test(model.name)) {
    const tree = Array.from(form.elements.sidecarFolder.files);
    const flat = Array.from(form.elements.sidecars.files);
    for (const file of tree.concat(flat)) {
      const path = file.webkitRelativePath?.split("/").slice(1).join("/") || file.name;
      if (path !== model.name) {
        body.append("sidecars[]", file, file.name);
        body.append("sidecar_paths[]", path);
      }
    }
  }
  submit.disabled = true;
  message($("upload-status"), "Uploading…");
  try {
    const result = await request("/assets/ingest", {method: "POST", body});
    $("upload-dialog").close();
    notice(`${result.name} · ${statusLabels[result.status] || result.status}`);
    await sync();
  } catch (error) { message($("upload-status"), error.message, true); }
  finally { submit.disabled = false; }
});

function buildLibrary(readyAssets) {
  const items = readyAssets.map((asset) => button(`+ ${asset.name}`, () => addAsset(asset)));
  $("ready-library").replaceChildren(...(items.length ? items : [element("p", "No matching scene-ready assets.", "muted")]));
}

function createRow(asset) {
  return {id: crypto.randomUUID(), assetId: asset.id, position: [0, 0, 0], rotationEulerDeg: [0, 0, 0],
    scale: [1, 1, 1], animationClip: asset.clips?.[0] || null, loopAnimation: true};
}

function ensureViewport() {
  if (!viewport) {
    viewport = new PipelineViewport($("scene-viewport"), (id, position) => {
      const row = objects.get(id);
      if (!row) return;
      row.position = position.map((number) => Number(number.toFixed(4)));
      if (selected === id) document.querySelectorAll("[data-position-index]").forEach((field) => {
        field.value = row.position[Number(field.dataset.positionIndex)];
      });
    });
    applyAspect();
  }
  return viewport;
}

async function addAsset(asset) {
  if (objects.size >= 12) return notice("Use up to 12 objects per render.", true);
  const row = createRow(asset);
  const count = objects.size;
  if (count) row.position[0] = count * 1.25;
  try {
    const view = ensureViewport();
    objects.set(row.id, row);
    selectObject(row.id);
    message($("viewport-status"), `Loading ${asset.name}…`);
    await view.load(row, asset);
    if (objects.has(row.id) && count === 0) view.frame();
    message($("viewport-status"), "");
  } catch (error) {
    objects.delete(row.id);
    selectObject(objects.keys().next().value);
    message($("viewport-status"), `Could not preview ${asset.name}: ${error.message}`, true);
  }
}

async function openPreview(asset) {
  const dialog = $("preview-dialog");
  $("preview-title").textContent = asset.name;
  message($("preview-status"), "Loading model…");
  dialog.showModal();
  try {
    preview = new PipelineViewport($("asset-viewport"));
    const active = preview;
    await active.load(createRow(asset), asset);
    if (preview === active) {
      active.frame();
      message($("preview-status"), "");
    }
  } catch (error) { message($("preview-status"), `Could not preview model: ${error.message}`, true); }
}

function selectObject(id) {
  selected = id;
  viewport?.select(id);
  $("scene-objects").replaceChildren(...Array.from(objects, ([key, row]) => {
    const control = button(cards.get(row.assetId)?.name || "Scene object", () => selectObject(key));
    control.setAttribute("aria-pressed", String(key === id));
    return control;
  }));
  buildInspector(objects.get(id));
}

function fieldGroup(row, property, label, min, max) {
  const group = element("fieldset", null, "xyz");
  group.append(element("legend", label));
  row[property].forEach((value, i) => {
    const fieldLabel = element("label", ["X", "Y", "Z"][i]);
    const input = element("input");
    input.type = "number";
    input.min = min;
    input.max = max;
    input.step = "any";
    input.value = value;
    if (property === "position") input.dataset.positionIndex = i;
    input.addEventListener("change", () => {
      if (input.value === "" || !input.checkValidity()) {
        input.value = row[property][i];
        return;
      }
      row[property][i] = Number(input.value);
      viewport.update(row);
    });
    fieldLabel.append(input);
    group.append(fieldLabel);
  });
  return group;
}

function buildInspector(row) {
  const target = $("object-inspector");
  if (!row) return target.replaceChildren(element("p", "Select an object."));
  const asset = cards.get(row.assetId);
  const clipLabel = element("label", "Animation clip");
  const clip = element("select");
  for (const value of [null, ...(asset.clips || [])]) {
    const option = element("option", value || "Rest pose");
    option.value = value || "";
    option.selected = value === row.animationClip;
    clip.append(option);
  }
  clip.addEventListener("change", () => { row.animationClip = clip.value || null; viewport.update(row); });
  clipLabel.append(clip);
  const loop = element("input");
  loop.type = "checkbox";
  loop.checked = row.loopAnimation;
  loop.addEventListener("change", () => { row.loopAnimation = loop.checked; viewport.update(row); });
  const loopLabel = element("label", null, "check-field");
  loopLabel.append(loop, "Loop clip");
  target.replaceChildren(
    fieldGroup(row, "position", "Position (m)", -10000, 10000),
    fieldGroup(row, "rotationEulerDeg", "Rotation (°)", -10000, 10000),
    fieldGroup(row, "scale", "Scale", 0.01, 100),
    clipLabel, loopLabel, button("Remove from scene", () => {
      objects.delete(row.id);
      viewport.remove(row.id);
      selectObject(objects.keys().next().value);
    })
  );
}

function resolution() {
  return $("render-options").elements.resolution.value.split("×").map(Number);
}
function applyAspect() {
  const [width, height] = resolution();
  viewport?.setAspect(width / height);
}

async function renderVideo(control) {
  if (renderPending) return;
  if (!objects.size || !viewport) return notice("Add a scene-ready asset before rendering.", true);
  const form = $("render-options");
  if (!form.reportValidity()) return;
  renderPending = true;
  control.disabled = true;
  try {
    const result = await request("/pipeline/renders", {method: "POST", body: {
      requestKey: crypto.randomUUID(), camera: viewport.cameraSpec(), objects: Array.from(objects.values()),
      renderEngine: form.elements.engine.value, lightingPreset: form.elements.lighting.value,
      resolution: resolution(), fps: Number(form.elements.fps.value), durationSeconds: Number(form.elements.seconds.value)
    }});
    notice(`Render #${result.id} · ${statusLabels[result.status] || result.status}`);
    await sync();
  } catch (error) { notice(error.message, true); }
  finally { renderPending = false; control.disabled = false; }
}

function buildRenders(renders) {
  // Preserve any video already playing while other queue entries change.
  const existing = new Map(Array.from($("render-list").children, (node) => [node.dataset.renderId, node]));
  const items = renders.map((render) => {
    const key = String(render.id);
    const prior = existing.get(key);
    if (prior?.dataset.state === render.status) return prior;
    const item = element("article", null, "panel render-item");
    item.dataset.renderId = key;
    item.dataset.state = render.status;
    item.append(element("h3", `Render #${key}`), element("p", statusLabels[render.status] || render.status));
    if (render.error) item.append(element("p", render.error, "error"));
    if (render.videoUrl) {
      const video = element("video");
      video.src = render.videoUrl;
      video.controls = true;
      video.preload = "none";
      item.append(video, link("Download MP4", render.downloadUrl));
    }
    return item;
  });
  const list = $("render-list");
  const retained = new Set(items);
  [...list.children].forEach((node) => { if (!retained.has(node)) node.remove(); });
  items.forEach((item, index) => {
    if (list.children[index] !== item) list.insertBefore(item, list.children[index] || null);
  });
  if (!items.length) list.append(element("p", "Completed and queued renders will appear here.", "muted"));
}

$("render-options").elements.resolution.addEventListener("change", applyAspect);
$("asset-search").addEventListener("input", () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(sync, 250);
});
hub.querySelector('[data-action="upload"]').addEventListener("click", () => openUpload({mode: "props"}));
hub.querySelector('[data-action="watcher"]').addEventListener("click", () => $("watcher-dialog").showModal());
hub.querySelector('[data-action="render"]').addEventListener("click", (event) => renderVideo(event.currentTarget));
for (const tool of ["orbit", "translate"]) {
  hub.querySelector(`[data-action="${tool}"]`).addEventListener("click", () => {
    if (!viewport) return;
    viewport.setTool(tool);
    ["orbit", "translate"].forEach((mode) => hub.querySelector(`[data-action="${mode}"]`).setAttribute("aria-pressed", mode === tool));
  });
}
hub.querySelector('[data-action="frame"]').addEventListener("click", () => viewport?.frame());
document.querySelectorAll("[data-close]").forEach((control) => control.addEventListener("click", () => control.closest("dialog").close()));
$("preview-dialog").addEventListener("close", () => { preview?.dispose(); preview = null; });
$("watcher-dialog").addEventListener("close", () => {
  $("watcher-token").value = "";
  ["watcher-token-label", "watcher-instructions", "copy-watcher"].forEach((id) => { $(id).hidden = true; });
});
$("issue-watcher").addEventListener("click", async (event) => {
  const control = event.currentTarget;
  control.disabled = true;
  try {
    const {token, expiresAt, ingestUrl, scope} = await request("/assets/pipeline/watcher_token", {method: "POST", body: {}});
    $("watcher-token").value = token;
    $("watcher-instructions").textContent = `read -rs LIGHTEK_INGEST_TOKEN; export LIGHTEK_INGEST_TOKEN\npython3 sync_exports.py "$HOME/Downloads" --url '${ingestUrl}' --scope '${scope}'`;
    ["watcher-token-label", "watcher-instructions", "copy-watcher"].forEach((id) => { $(id).hidden = false; });
    message($("watcher-status"), `Paste the token after the first command. Expires ${new Date(expiresAt).toLocaleString()}.`);
  } catch (error) { message($("watcher-status"), error.message, true); }
  finally { control.disabled = false; }
});
$("copy-watcher").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("watcher-token").value);
    message($("watcher-status"), "Upload token copied.");
  } catch { message($("watcher-status"), "Clipboard unavailable. Select the upload token to copy it.", true); }
});

sync();
setInterval(() => { if (!document.hidden) sync(); }, 3500);
