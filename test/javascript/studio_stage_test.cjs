const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { chromium } = require("playwright");
(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_PATH
      ? { executablePath: process.env.CHROME_PATH }
      : {}),
    args: [
      "--no-sandbox",
      "--use-gl=angle",
      "--use-angle=swiftshader",
      "--enable-unsafe-swiftshader",
      "--autoplay-policy=no-user-gesture-required",
    ],
  });
  try {
    const page = await browser.newPage(),
      errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.route("https://stage.test/**", (route) => {
      const p = new URL(route.request().url()).pathname;
      if (p === "/")
        return route.fulfill({
          contentType: "text/html",
          body: '<script type="importmap">{"imports":{"three":"/lightek/vendor/three/three.module.js"}}</script><main>Stage test</main>',
        });
      if (p === "/api/lightek/pwa/assets/1/proxy")
        return route.fulfill({
          contentType: "model/gltf-binary",
          body: fs.readFileSync("/tmp/native-viewport-proof.glb"),
        });
      return route.fulfill({
        contentType: "application/javascript",
        body: fs.readFileSync(path.join("public", p)),
      });
    });
    await page.goto("https://stage.test/");
    await page.evaluate(async () => {
      const { StageComposer } = await import("/lightek/live/stage.js");
      const THREE = await import("/lightek/vendor/three/three.module.js");
      window.stage = new StageComposer(320, 180);
      await stage.load("/api/lightek/pwa/assets/1/proxy");
      stage.camera.position.set(0, -8, 0);
      stage.camera.lookAt(0, 0, 0);
      stage.model.traverse((o) => {
        if (o.isMesh) {
          o.material = new THREE.MeshBasicMaterial({ color: 0x0000ff });
        }
      });
      document.body.append(stage.renderer.domElement);
      const source = document.createElement("canvas");
      source.width = 160;
      source.height = 90;
      const ctx = source.getContext("2d");
      ctx.fillStyle = "#00ff00";
      ctx.fillRect(0, 0, 160, 90);
      ctx.fillStyle = "#ff0000";
      ctx.fillRect(60, 25, 40, 40);
      window.subject = document.createElement("video");
      subject.muted = true;
      subject.srcObject = source.captureStream(24);
      await subject.play();
      window.subjectCanvas = source;
      window.pixel = (depth) => {
        stage.setSubject(subject, {
          key: true,
          color: "#00ff00",
          threshold: 0.2,
          x: 0,
          depth,
          z: 0,
          height: 4,
        });
        const canvas = stage.render();
        const temp = document.createElement("canvas");
        temp.width = 320;
        temp.height = 180;
        const c = temp.getContext("2d");
        c.drawImage(canvas, 0, 0);
        return [...c.getImageData(160, 90, 1, 1).data];
      };
    });
    await page.waitForTimeout(150);
    await page.evaluate(() => pixel(-2));
    await page.waitForTimeout(150);
    const front = await page.evaluate(() => pixel(-2));
    await page.evaluate(() => pixel(2));
    await page.waitForTimeout(100);
    const behind = await page.evaluate(() => pixel(2));
    assert(front[0] > 200 && front[2] < 30, JSON.stringify(front));
    assert(behind[2] > 200 && behind[0] < 30, JSON.stringify(behind));
    const invalid = await page.evaluate(async () => {
      try {
        await stage.load("https://outside.test/model.glb");
        return false;
      } catch {
        return true;
      }
    });
    assert(invalid);
    await page.screenshot({ path: "/tmp/lightek-stage-depth.png" });
    await page.evaluate(() => {
      subject.srcObject.getTracks().forEach((t) => t.stop());
      stage.dispose();
    });
    assert.deepEqual(errors, []);
    console.log(
      "STUDIO_STAGE_PASS real_glb chroma_key video_texture foreground_background_depth cleanup",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
