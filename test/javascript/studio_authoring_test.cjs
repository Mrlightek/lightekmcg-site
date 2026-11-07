const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  path = require("node:path");
const { chromium } = require("playwright");
const fixture = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0;background:#080e16;color:#eee;font:14px system-ui}#app{max-width:1200px;margin:auto;padding:12px}button{cursor:pointer;padding:8px}.btn{color:#eee;background:#26384b;border:1px solid #52677e;border-radius:6px}.btn.p{background:#66512d}.eb{font-size:10px;color:#d4bf95}.pwa-post-actions{display:flex;gap:8px;flex-wrap:wrap}</style><link rel="stylesheet" href="/lightek/studio-authoring.css"></head><body><main id="app"></main><script>
const app=document.getElementById('app'),A={},ST={loaded:true,selectedObjectId:1},requests=[];
const E=v=>String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));const toast=v=>window.lastToast=v;
const scene={id:7,lock_version:0,settings:{frame_start:1,frame_end:24,native_revision:0},objects:[{id:1,name:'Hero mesh',object_type:'native_object',definition:{native_type:'MESH',blender_object_name:'Hero',location:[0,0,0],rotation:[0,0,0],scale:[1,1,1],mesh:{vertex_count:8,face_count:6,vertices:[[0,1,1,1],[1,-1,1,1]],faces:[[0,0,1,2,3]]},graphs:[{scope:'material',slot:0,graph:{name:'Hero surface',nodes:[{name:'Principled BSDF',type:'ShaderNodeBsdfPrincipled',inputs:[{index:0,name:'Base Color'}],outputs:[{index:0,name:'BSDF'}]},{name:'Material Output',type:'ShaderNodeOutputMaterial',inputs:[{index:0,name:'Surface'}],outputs:[]}],links:[{from:'Principled BSDF',to:'Material Output',input:0,output:0}]}}]}},{id:2,name:'Hero rig',object_type:'native_object',definition:{native_type:'ARMATURE',bones:[{name:'Root',parent:null},{name:'Hand',parent:'Root'}]}}]};const record={scene,project:{id:1}};
window.LightekStudioApp={tools:()=>'',prepare:()=>{},setQuote:q=>window.quote=q};window.LightekStudioViewportBridge={snapshot:()=>({sceneId:7,objects:scene.objects})};
const studioCurrentSceneId=()=>7,studioSceneRecord=()=>record,studioWorkspaceSelectedObject=s=>s?.objects.find(o=>o.id===ST.selectedObjectId);
A.studioLoad=async()=>{};A.studioBlenderDraftPreview=()=>{};
const nevaeh={execute:async request=>{requests.push(request);const p=request.payload;if(request.capability.endsWith('authoring.edit')){scene.lock_version++;scene.settings.native_revision++;const o=scene.objects.find(o=>o.id===p.object_id)||scene.objects[0];o.definition.authoring_commands||=[];if(p.command)o.definition.authoring_commands.push(p.command);return {result:{object_id:o.id}};}if(request.capability.endsWith('authoring.preview'))return {result:{status:'completed',native_revision:scene.settings.native_revision,authoring:{},proxy_url:'/rails/active_storage/blobs/redirect/signed/scene.glb'}};return {result:{operation_id:9,quote:{principal_cents:500}}};}};
function render(){app.innerHTML=LightekStudioApp.tools(record)}app.addEventListener('click',e=>{const b=e.target.closest('[data-a]');if(b&&A[b.dataset.a])A[b.dataset.a](b)});
</script><script src="/lightek/studio-authoring.js"></script><script>location.hash='#/studio/7';render()</script></body></html>`;
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
