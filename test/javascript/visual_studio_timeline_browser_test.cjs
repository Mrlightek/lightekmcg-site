const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { chromium } = require("playwright");

const root = path.resolve(__dirname, "../..");
const template = fs.readFileSync(path.join(root, "app/views/studio/animation/scenes/show.html.erb"), "utf8");
const workspace = template.slice(template.indexOf('<div class="visual-studio"'))
  .replace(/<%= studio_animation_scene_path.*?%>/, "/scene")
  .replace(/<%= studio_animation_assets_path.*?%>/, "/assets")
  .replace(/<%= studio_animation_scene_renders_path.*?%>/, "/renders")
  .replace(/<%= studio_animation_scenes_path.*?%>/, "/library")
  .replace(/<%= .*?%>/g, "");
const html = `<!doctype html><meta charset="utf-8"><meta name="csrf-token" content="test">
<link rel="stylesheet" href="/lightek/visual-studio/studio.css">
<script type="importmap">{"imports":{"three":"/lightek/vendor/three/three.module.js"}}</script>
<script type="module" src="/lightek/visual-studio/studio.js"></script>
${workspace}`;

async function main() {
  const browser = await chromium.launch({
    executablePath: process.env.STUDIO_CHROMIUM_EXECUTABLE,
    args: ["--no-sandbox", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"]
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1400, height: 1100 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    const scene = {
      name: "Test scene", lock_version: 0,
      scene_spec: {
        aspect_ratio: "9:16", fps: 24, duration_ms: 1020,
        camera: { position: [0, -8, 0], rotation: [90, 0, 0], lens: 35, keyframes: [] },
        layers: [{
          asset_id: 1, dimension_mode: "2d", position: [0, 0, 0], rotation: [0, 0, 0], scale: [1, 1, 1], z_layer: 0, keyframes: [],
          mouth: { position: [0, 0, 0], scale: [1, 1, 1], variants: { X: 2, A: 2 }, cues: [
            { start_ms: 0, end_ms: 50, viseme: "A" }, { start_ms: 50, end_ms: 180, viseme: "B" }
          ] }
        }]
      }
    };
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="white"/></svg>';
    const assets = [
      { id: 1, name: "Character", dimension_mode: "2d", animation_role: "character", filename: "card.svg", file_url: "/card.svg" },
      { id: 2, name: "Mouth", dimension_mode: "2d", animation_role: "viseme", filename: "card.svg", file_url: "/card.svg" },
      { id: 3, name: "Native rig", dimension_mode: "3d", animation_role: "character", filename: "rig.blend",
        file_url: "/rig.blend", source_revision: 91, preview_request_url: "/pose-preview" },
      { id: 4, name: "Animated GLTF", dimension_mode: "3d", animation_role: "character", filename: "model.gltf",
        file_url: "/model.gltf" }
    ];
    const poseRequests = [];
    const clipData = Buffer.from(new Float32Array([0, 1, 0, 0, 0, 1, 0, 0]).buffer);
    const gltf = {
      asset: { version: "2.0" }, scene: 0, scenes: [{ nodes: [0] }], nodes: [{ name: "Original" }],
      buffers: [{ byteLength: clipData.length, uri: "data:application/octet-stream;base64," + clipData.toString("base64") }],
      bufferViews: [{ buffer: 0, byteLength: 8 }, { buffer: 0, byteOffset: 8, byteLength: 24 }],
      accessors: [
        { bufferView: 0, componentType: 5126, count: 2, type: "SCALAR", min: [0], max: [1] },
        { bufferView: 1, componentType: 5126, count: 2, type: "VEC3" }
      ],
      animations: [{ name: "Actual clip", samplers: [{ input: 0, output: 1 }],
        channels: [{ sampler: 0, target: { node: 0, path: "translation" } }] }]
    };
    await page.route("http://localhost:18447/**", async route => {
      const url = new URL(route.request().url()).pathname;
      if (url === "/scene") {
        if (route.request().method() === "PATCH") {
          const { lock_version, ...edit } = route.request().postDataJSON().scene;
          assert.equal(lock_version, scene.lock_version);
          Object.assign(scene, edit, { lock_version: lock_version + 1 });
        }
        return route.fulfill({ json: scene });
      }
      if (url === "/assets") return route.fulfill({ json: assets });
      if (url === "/renders") return route.fulfill({ json: [] });
      if (url === "/pose-preview") {
        if (route.request().method() === "POST") {
          const pose = route.request().postDataJSON();
          poseRequests.push(pose);
          return route.fulfill({ json: { preview_status: "ready", preview_kind: "static",
            evaluated_frame: pose.pose_frame, preview_url: "/pose.glb", clips: [] } });
        }
        return route.fulfill({ json: { preview_status: "missing", clips: [] } });
      }
      if (url === "/model.gltf") return route.fulfill({ json: gltf });
      if (url === "/pose.glb") return route.fulfill({ json: { ...gltf, animations: [] } });
      if (url === "/card.svg") return route.fulfill({ body: svg, contentType: "image/svg+xml" });
      if (url.startsWith("/lightek/")) return route.fulfill({
        path: path.join(root, "public", url),
        contentType: url.endsWith(".css") ? "text/css" : "application/javascript"
      });
      return route.fulfill({ body: html, contentType: "text/html" });
    });
    await page.goto("http://localhost:18447/");
    await page.locator(".vs-cue").first().waitFor();
    const cue = index => page.locator(".vs-cue").nth(index);
    const edit = (label, value) => page.getByLabel(label, { exact: true }).evaluate((input, next) => {
      input.value = next;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }, value);
    const contains = (item, text) => item.waitFor({ state: "visible" }).then(async () => assert.match(await item.getAttribute("aria-label"), text));

    await cue(1).click();
    await edit("End frame (inclusive)", "4");
    await contains(cue(1), /50–166 ms/);

    await cue(0).click();
    await edit("End (ms, exclusive)", "39");
    await edit("End frame (inclusive)", "2");
    await contains(cue(0), /0–50 ms/);
    await contains(cue(1), /50–166 ms/);

    await cue(1).click();
    await edit("Start (ms)", "49");
    await page.getByText("Mouth cues cannot overlap on the same layer.").waitFor();
    await contains(cue(1), /50–166 ms/);

    const block = await cue(1).boundingBox();
    const rail = await cue(1).locator("..").boundingBox();
    await page.mouse.move(block.x + block.width - 2, block.y + block.height / 2);
    await page.mouse.down();
    await page.mouse.move(block.x + block.width - 2 + rail.width / 25, block.y + block.height / 2);
    await page.mouse.up();
    await contains(cue(1), /50–208 ms/);

    page.once("dialog", dialog => dialog.accept());
    await page.locator("[data-cue-file]").setInputFiles({
      name: "rhubarb.json", mimeType: "application/json",
      buffer: Buffer.from(JSON.stringify({ mouthCues: [{ start: 1.005, end: 1.020, value: "A" }] }))
    });
    const warning = page.getByRole("button", { name: "A · 1005–1020 ms · No rendered frames" });
    await warning.click();
    await page.getByText("No rendered frames. Move or extend this cue to cover a frame.").waitFor();
    await edit("Start (ms)", "1000");
    await contains(cue(0), /1000–1020 ms · frames 25–25/);
    await page.locator("[data-save]").click();
    await page.getByText("Saved", { exact: true }).waitFor();
    assert.deepEqual(scene.scene_spec.layers[0].mouth.cues, [{ start_ms: 1000, end_ms: 1020, viseme: "A" }]);

    // From the last frame, Play restarts at frame 1. Use a virtual clock to
    // distinguish the authored 1020 ms from the encoded 1041.667 ms.
    assert.match(await page.locator("[data-time]").textContent(), /1.042 s$/);
    await page.clock.install();
    await page.clock.pauseAt(new Date(Date.now() + 1000));
    await page.locator("[data-play]").evaluate(control => control.click());
    await page.clock.runFor(1030);
    assert.equal(await page.locator("[data-play]").textContent(), "Pause");
    assert.equal(await page.locator("[data-frame]").textContent(), "Frame 25 / 25");
    await page.clock.runFor(35);
    assert.equal(await page.locator("[data-play]").textContent(), "Play");
    await page.clock.resume();
    const add = name => page.locator(".vs-asset-list li").filter({ hasText: name }).getByRole("button", { name: "Add layer" }).click();
    await add("Native rig");
    await edit("Native action name", "Walk");
    await edit("Freeze at model frame", "12");
    await page.getByRole("button", { name: "Build pose preview" }).click();
    await page.locator("[data-preview-message]").getByText(/Static Blender pose preview · frame 12/).waitFor();
    assert.deepEqual(poseRequests, [{ source_revision: 91, fps: 24, action_name: "Walk", pose_frame: 12 }]);
    assert.equal(await page.getByLabel("Model action").count(), 0);

    await page.locator("[data-fps]").selectOption("30");
    await page.getByRole("button", { name: "Build pose preview" }).waitFor();
    await page.getByRole("button", { name: "Build pose preview" }).click();
    await page.locator("[data-preview-message]").getByText(/Static Blender pose preview · frame 12/).waitFor();
    assert.deepEqual(poseRequests[1], { source_revision: 91, fps: 30, action_name: "Walk", pose_frame: 12 });

    await add("Animated GLTF");
    await page.getByLabel("Model action").waitFor();
    assert.deepEqual(await page.getByLabel("Model action").locator("option").allTextContents(), ["Default", "Actual clip"]);
    assert.deepEqual(errors, []);
    console.log("Visual Studio timeline browser checks passed");
  } finally {
    await browser.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
