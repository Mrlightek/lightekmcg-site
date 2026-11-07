(() => {
  function boot() {
    const root = document.querySelector("[data-studio-workstation]");
    if (!root || root.dataset.wired) return;
    root.dataset.wired = "true";
    const q = (s) => root.querySelector(s),
      frame = q("[data-desktop]"),
      message = q("[data-status]"),
      error = q("[data-error]");
    let timer = null,
      closed = false,
      connected = false,
      busy = false;
    const headers = () => ({
      Accept: "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token":
        document.querySelector("meta[name=csrf-token]")?.content || "",
    });
    async function request(url, method = "GET", payload = {}) {
      const response = await fetch(url, {
        method,
        credentials: "same-origin",
        headers: headers(),
        ...(method === "GET" ? {} : { body: JSON.stringify(payload) }),
      });
      const data = await response.json();
      if (!response.ok)
        throw Error(data.error || "Workstation request failed.");
      return data;
    }
    const fail = (e) => {
      error.hidden = false;
      error.textContent = e.message;
    };
    async function connect() {
      try {
        const data = await request(root.dataset.ticketUrl, "POST");
        if (
          !/^\/studio-workstations\/[a-f0-9]{32}\/bootstrap\?ticket=/.test(
            data.url,
          )
        )
          throw Error("Invalid workstation connection.");
        frame.src = data.url;
        frame.hidden = false;
        q("[data-placeholder]").hidden = true;
        connected = true;
      } catch (e) {
        fail(e);
      }
    }
    async function poll() {
      try {
        const data = await request(root.dataset.statusUrl);
        if (closed) return;
        message.textContent =
          {
            starting: "Queued for native workstation preparation…",
            building: "Blender is preparing your native source…",
            ready: "Native editor ready",
            saving: "Saving in Blender and importing your Studio version…",
            stopped: "Workstation closed",
            expired: "Workstation expired",
            failed: "Workstation failed",
          }[data.status] || data.status;
        q("[data-save]").disabled = data.status !== "ready";
        q("[data-connect]").disabled = !["ready", "saving"].includes(
          data.status,
        );
        q("[data-stop]").disabled = ["stopped", "expired", "failed"].includes(
          data.status,
        );
        if (data.error) {
          error.textContent = data.error;
          error.hidden = false;
        }
        if (data.status === "ready" && !connected) await connect();
        if (data.saved_scene_id) {
          const link = q("[data-saved-project]");
          link.href =
            "/lightek/index.html#/studio/" + Number(data.saved_scene_id);
          link.hidden = false;
          link.textContent =
            "Open saved production" +
            (data.saved_at
              ? " · " + new Date(data.saved_at).toLocaleTimeString()
              : "");
          q("[data-saved-library]").hidden = false;
        }
        if (["stopped", "expired", "failed"].includes(data.status)) {
          frame.src = "about:blank";
          frame.hidden = true;
          return;
        }
        timer = setTimeout(poll, 2000);
      } catch (e) {
        fail(e);
        if (!closed) timer = setTimeout(poll, 5000);
      }
    }
    root.querySelectorAll("[data-workspace]").forEach((button) =>
      button.addEventListener("click", async () => {
        try {
          await request(root.dataset.workspaceUrl, "POST", {
            task: button.dataset.workspace,
          });
          message.textContent =
            "Opening " + button.textContent + " in Blender…";
        } catch (e) {
          fail(e);
        }
      }),
    );
    q("[data-connect]").addEventListener("click", connect);
    q("[data-save]").addEventListener("click", async () => {
      if (busy) return;
      busy = true;
      q("[data-save]").disabled = true;
      error.hidden = true;
      try {
        await request(root.dataset.saveUrl, "POST");
        clearTimeout(timer);
        await poll();
      } catch (e) {
        fail(e);
      } finally {
        busy = false;
      }
    });
    q("[data-stop]").addEventListener("click", async () => {
      try {
        await request(root.dataset.stopUrl, "DELETE");
        closed = true;
        clearTimeout(timer);
        frame.src = "about:blank";
        frame.hidden = true;
        message.textContent = "Workstation closed";
        q("[data-save]").disabled = true;
        q("[data-connect]").disabled = true;
        q("[data-stop]").disabled = true;
      } catch (e) {
        fail(e);
      }
    });
    q("[data-fullscreen]").addEventListener("click", () =>
      frame.requestFullscreen?.().catch(fail),
    );
    const cleanup = () => {
      closed = true;
      clearTimeout(timer);
      frame.src = "about:blank";
      delete root.dataset.wired;
    };
    document.addEventListener("turbo:before-cache", cleanup, { once: true });
    window.addEventListener("pagehide", cleanup, { once: true });
    poll();
  }
  document.addEventListener("turbo:load", boot);
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", boot, { once: true });
  else boot();
})();
