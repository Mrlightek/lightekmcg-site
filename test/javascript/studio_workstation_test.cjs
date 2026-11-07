const assert = require("node:assert/strict"),
  fs = require("node:fs"),
  { JSDOM } = require("jsdom");
const dom = new JSDOM(
  `<meta name="csrf-token" content="proof"><main data-studio-workstation data-status-url="/status" data-ticket-url="/ticket" data-save-url="/save" data-workspace-url="/workspace" data-stop-url="/stop"><iframe data-desktop hidden></iframe><div data-placeholder></div><p data-status></p><p data-error hidden></p><button data-save></button><button data-connect></button><button data-stop></button><button data-fullscreen></button><button data-workspace="uv">UV Editing</button><a data-saved-project hidden></a><a data-saved-library hidden></a></main>`,
  { url: "https://studio.test/", runScripts: "outside-only" },
);
const w = dom.window,
  calls = [];
let state = "ready",
  saved = false;
w.fetch = async (url, options) => {
  calls.push({ url, options });
  assert.equal(options.credentials, "same-origin");
  assert.equal(options.headers["X-CSRF-Token"], "proof");
  return {
    ok: true,
    json: async () =>
      url === "/ticket"
        ? {
            url:
              "/studio-workstations/" +
              "a".repeat(32) +
              "/bootstrap?ticket=proof",
          }
        : url === "/status"
          ? {
              status: state,
              ...(saved
                ? { saved_scene_id: 42, saved_at: "2026-11-07T12:00:00Z" }
                : {}),
            }
          : {},
  };
};
const tick = () => new Promise((resolve) => setImmediate(resolve));
(async () => {
  w.eval(fs.readFileSync("public/lightek/workstation.js", "utf8"));
  w.document.dispatchEvent(new w.Event("DOMContentLoaded"));
  await tick();
  await tick();
  const q = (s) => w.document.querySelector(s);
  assert.equal(q("[data-desktop]").hidden, false);
  assert.match(q("[data-desktop]").src, /bootstrap/);
  q("[data-workspace]").click();
  await tick();
  assert.deepEqual(JSON.parse(calls.at(-1).options.body), { task: "uv" });
  saved = true;
  q("[data-save]").click();
  await tick();
  await tick();
  assert(calls.some((c) => c.url === "/save" && c.options.method === "POST"));
  assert.equal(q("[data-saved-project]").hash, "#/studio/42");
  assert.equal(q("[data-saved-library]").hidden, false);
  q("[data-stop]").click();
  await tick();
  assert.equal(calls.at(-1).options.method, "DELETE");
  assert.equal(q("[data-desktop]").src, "about:blank");
  assert(q("[data-save]").disabled);
  assert.match(q("[data-status]").textContent, /closed/);
  console.log(
    "STUDIO_WORKSTATION_PASS authenticated connect workspace save Library close",
  );
  dom.window.close();
})().catch((e) => {
  console.error(e);
  dom.window.close();
  process.exitCode = 1;
});
