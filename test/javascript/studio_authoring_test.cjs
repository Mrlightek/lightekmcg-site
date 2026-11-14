const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { chromium } = require("playwright");
const fixture = require('./fixtures/studio_authoring_fixture.cjs');
(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(process.env.CHROME_PATH
      ? { executablePath: process.env.CHROME_PATH }
      : {}),
    args: ["--no-sandbox"],
  });
  try {
    const page = await browser.newPage({
        viewport: { width: 1280, height: 900 },
      }),
      errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.route("https://authoring.test/**", (r) => {
      const p = new URL(r.request().url()).pathname;
      r.fulfill({
        contentType: p.endsWith(".js")
          ? "application/javascript"
          : p.endsWith(".css")
            ? "text/css"
            : "text/html",
        body: p === "/" ? fixture : fs.readFileSync(path.join("public", p)),
      });
    });
    await page.goto("https://authoring.test/");
    await page
      .getByRole("region", { name: "Native production authoring" })
      .waitFor();
    const form = page.locator("[data-authoring-form=mesh_extrude]");
    await form.locator("[name=indices]").fill("0");
    await form.locator("[name=delta_2]").fill("0.5");
    await form.locator("button").click();
    await page.waitForFunction(() => requests.length === 1);
    let request = await page.evaluate(() => requests[0]);
    assert.equal(request.payload.command.kind, "mesh_extrude");
    assert.deepEqual(request.payload.command.delta, [0, 0, 0.5]);
    assert.equal(request.payload.lock_version, 0);
    await page.getByRole("button", { name: "Sculpt", exact: true }).click();
    await page.evaluate(() =>
      window.dispatchEvent(
        new CustomEvent("lightek:authoring-pick", {
          detail: { sceneId: 7, point: [0.1, 0.2, 0.3] },
        }),
      ),
    );
    assert.equal(await page.locator("[name=center_0]").inputValue(), "0.1000");
    await page
      .getByRole("button", { name: "Apply sculpt stroke", exact: true })
      .click();
    await page.waitForFunction(() => requests.length === 2);
    await page.evaluate(() => {
      ST.selectedObjectId = 2;
      render();
    });
    await page
      .getByRole("button", { name: "Rig & weights", exact: true })
      .click();
    const pose = page.locator("[data-authoring-form=bone_pose]");
    await pose.locator("[name=bone]").selectOption("Hand");
    await pose.locator("[name=rotation_2]").fill("45");
    await pose.locator("[name=frame]").fill("12");
    await pose.locator("button").click();
    await page.waitForFunction(() => requests.length === 3);
    request = await page.evaluate(() => requests.at(-1));
    assert.equal(request.payload.command.bone, "Hand");
    assert.equal(request.payload.command.frame, 12);
    await page.evaluate(() => {
      ST.selectedObjectId = 1;
      render();
    });
    await page
      .getByRole("button", { name: "Node graphs", exact: true })
      .click();
    assert.equal(
      await page
        .getByRole("img", { name: "material node connections" })
        .count(),
      1,
    );
    const add = page.locator("[data-authoring-form=node_add]");
    await add.locator("[name=scope]").selectOption("geometry");
    await add.locator("[name=type]").selectOption("GeometryNodeMeshCube");
    await add.locator("button").click();
    await page.waitForFunction(() => requests.length === 4);
    request = await page.evaluate(() => requests.at(-1));
    assert.equal(request.payload.command.scope, "geometry");
    await page
      .getByRole("button", {
        name: "Select output Principled BSDF 0",
        exact: true,
      })
      .click();
    await page
      .getByRole("button", {
        name: "Connect input Material Output 0",
        exact: true,
      })
      .click();
    await page.waitForFunction(() => requests.length === 5);
    request = await page.evaluate(() => requests.at(-1));
    assert.equal(request.payload.command.kind, "node_link");
    await page
      .getByRole("button", { name: "Update Blender viewport", exact: true })
      .click();
    await page.waitForFunction(() =>
      document
        .querySelector("[data-authoring-status]")
        .textContent.includes("updated"),
    );
    assert.match(
      await page.evaluate(
        () =>
          LightekStudioViewportBridge.snapshot().objects.find((o) => o.id < 0)
            ?.definition.asset_proxy_url || "",
      ),
      /^\/rails\/active_storage\/blobs\//,
    );
    await page.screenshot({
      path: "/tmp/lightek-authoring-desktop.png",
      fullPage: true,
    });
    await page.setViewportSize({ width: 390, height: 844 });
    assert(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    );
    await page.screenshot({
      path: "/tmp/lightek-authoring-mobile.png",
      fullPage: true,
    });
    await page.getByRole('button',{name:'Model',exact:true}).click();
    const skew=page.locator('[data-authoring-form=mesh_skew]');
    const before=await page.evaluate(()=>requests.length);
    await skew.locator('[name=factor_value]').fill('0.75');
    assert.equal(await page.evaluate(()=>requests.length),before,'dragging does not submit an engine job');
    assert.equal((await page.evaluate(()=>LightekStudioMeshDraft())).command.factor,.75);
    await page.evaluate(()=>render());
    assert.equal(await skew.locator('[name=factor_value]').inputValue(),'0.75','background rendering retains the draft');
    await skew.getByRole('button',{name:'Reset preview'}).click();
    assert.equal(await skew.locator('[name=factor_value]').inputValue(),'0');
    assert.equal(await page.evaluate(()=>LightekStudioMeshDraft()),null);
    await skew.locator('[name=factor_value]').fill('-0.5');
    await skew.getByRole('button',{name:'Apply skew object'}).click();
    await page.waitForFunction(n=>requests.length===n+1,before);
    assert.deepEqual((await page.evaluate(()=>requests.at(-1))).payload.command,{kind:'mesh_skew',axis:'X',source_axis:'Z',factor:-.5,indices:[]});
    assert.equal(await page.evaluate(()=>LightekStudioMeshDraft()),null);
    // Dashboard tokens control the specialized authoring panel in either palette.
    await page.evaluate(()=>{
      const host=document.createElement('div');host.id='lightek-studio-dashboard';app.before(host);host.append(app);
    });
    for(const palette of [{bg:'#ffffff',text:'#172033',field:'#f4f6fa'},{bg:'#171923',text:'#eef0f6',field:'#10121a'}]) {
      await page.evaluate(p=>document.documentElement.style.cssText=`--dd-sidebar-bg:${p.bg};--dd-card-bg:${p.bg};--dd-text-primary:${p.text};--dd-text-secondary:${p.text};--dd-input-bg:${p.field};--dd-input-text:${p.text};--dd-border:#556677;--dd-input-border:#556677;--dd-accent:#8965ce;--dd-button-text:#ffffff`,palette);
      assert.equal(await page.locator('.sa-dock').evaluate(el=>getComputedStyle(el).backgroundColor),palette.bg==='#ffffff'?'rgb(255, 255, 255)':'rgb(23, 25, 35)');
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
      await page.screenshot({path:`/tmp/lightek-authoring-${palette.bg==='#ffffff'?'light':'dark'}.png`,fullPage:true});
    }
    assert.deepEqual(errors, []);
    console.log(
      "STUDIO_AUTHORING_UI_PASS mesh sculpt picked_coordinates rig_keyframe node_graph preview mobile",
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
