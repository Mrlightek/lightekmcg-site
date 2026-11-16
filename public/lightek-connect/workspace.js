(() => {
  "use strict";
  const root = document.getElementById("lightek-connect");
  if (!root) return;
  const platform = root.dataset.platform;
  const api = root.dataset.api;
  class RequestError extends Error {
    constructor(message, status) {super(message); this.status = status;}
  }
  const el = (tag, text, parent = root) => {
    const node = document.createElement(tag); if (text) node.textContent = text;
    parent.append(node); return node;
  };
  const request = async (path, method = "GET", body) => {
    const headers = {"Content-Type": "application/json", Accept: "application/json"};
    if (platform === "shopify") headers.Authorization = `Bearer ${await window.shopify.idToken()}`;
    else headers["X-WP-Nonce"] = root.dataset.nonce;
    let response;
    try {response = await fetch(`${api}${path}`, {method, headers, credentials: "same-origin", body: body ? JSON.stringify(body) : undefined});}
    catch (_) {throw new RequestError("Unable to reach Lightek. Check your connection and try again.");}
    if (response.status === 204) return {};
    let data;
    try {data = await response.json();} catch (_) {
      if (response.ok) throw new RequestError("Lightek returned an unexpected response. Try again shortly.");
      data = {};
    }
    if (!response.ok) throw new RequestError(data.error || data.message || (response.status === 401 ? "Connect your agency to continue." : "Lightek is temporarily unavailable. Try again shortly."), response.status);
    if (!data || typeof data !== "object" || Array.isArray(data)) throw new RequestError("Lightek returned an unexpected response. Try again shortly.");
    return data;
  };
  let status;
  const action = (label, parent, fn) => {
    const button = el("button", label, parent); button.type = "button";
    button.onclick = async () => {button.disabled = true; status.textContent = "Working…";
      try {await fn();} catch (error) {status.textContent = error.message;} finally {button.disabled = false;}
    }; return button;
  };
  const destination = (data, parent) => {
    const url = new URL(data.url);
    if (url.protocol !== "https:" || url.username || url.password) throw new Error("Invalid destination");
    parent.querySelectorAll(".lc-link").forEach(link => link.remove());
    const a = el("a", "Continue to Lightek management", parent); a.className = "lc-link";
    a.href = url.href; a.target = "_blank"; a.rel = "noopener noreferrer";
    status.textContent = "Management link ready. Continue within ten minutes and verify your Lightek identity.";
    const lifetime = Number(data.expires_in);
    window.setTimeout(() => {a.remove();}, Number.isFinite(lifetime) && lifetime > 0 ? Math.min(lifetime, 600) * 1000 : 600000);
  };
  const shell = () => {root.replaceChildren(); el("h1", "Lightek Connect"); status = el("p", "", root); status.className = "lc-status"; status.setAttribute("role", "status");};
  const pairing = (message = "") => {
    shell(); el("p", "Create a connection code in your Lightek Dashboard → Lightek Connect, then paste it here.");
    status.textContent = message;
    const input = el("input"); input.type = "password"; input.autocomplete = "off"; input.placeholder = "Connection code"; input.setAttribute("aria-label", "Connection code");
    action("Connect agency", root, async () => {await request("/pair", "POST", {platform, code: input.value}); input.value = ""; await initialLoad();});
    const link = el("a", "Open Lightek Connect settings"); link.href = platform === "wordpress" ? root.dataset.origin + "/dashboard/connect" : "/dashboard/connect"; link.target = "_blank"; link.rel = "noopener noreferrer";
  };
  const load = async () => {
    let data;
    try {data = await request("/workspace");}
    catch (error) {
      if (error.status === 401) {pairing(error.message); return;}
      throw error;
    }
    shell(); el("p", `Connected to ${data.agency.name}`);
    const nav = el("div");
    data.capabilities.forEach(cap => action(cap.label, nav, async () => destination(await request("/dashboard", "POST", {path: cap.path}), nav)));
    const grid = el("div"); grid.className = "lc-grid";
    const sites = el("section", "", grid); el("h2", "Client websites", sites);
    if (!data.sites.length) el("p", "No client websites yet. Open Clients & agencies or Provision client hosting to get started.", sites);
    data.sites.forEach(site => {
      const row = el("article", "", sites); const title = el("strong", site.name, row); el("small", site.host, row);
      action("Manage client instance", row, async () => destination(await request(`/sites/${site.id}/management`, "POST"), row));
      const name = el("input", "", row); name.value = site.name; name.maxLength = 160; name.setAttribute("aria-label", `Website name for ${site.host}`);
      action("Save website name", row, async () => {const saved = await request(`/sites/${site.id}`, "PATCH", {name: name.value});
        if (saved.verified && typeof saved.name === "string") {title.textContent = saved.name; name.value = saved.name;}
        status.textContent = saved.verified ? "Website name saved and verified." : "Save could not be verified.";
      });
    });
    const launches = el("section", "", grid); el("h2", "Recent deployments", launches);
    if (!data.launches.length) el("p", "No deployments yet.", launches);
    data.launches.forEach(launch => {const row = el("article", "", launches); el("strong", launch.name, row); el("small", `${launch.domain} · ${launch.status}`, row);});
    action("Refresh", root, load);
    action("Disconnect", root, async () => {await request("", "DELETE"); pairing();});
  };
  const initialLoad = async () => {
    try {await load();}
    catch (error) {
      shell(); status.textContent = error.message;
      el("p", "Your existing connection has been kept. Retry when the service is available.");
      action("Retry connection", root, initialLoad);
    }
  };
  shell(); initialLoad();
})();
