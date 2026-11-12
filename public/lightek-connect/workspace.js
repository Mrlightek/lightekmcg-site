(() => {
  "use strict";
  const root = document.getElementById("lightek-connect");
  if (!root) return;
  const platform = root.dataset.platform;
  const api = root.dataset.api;
  const el = (tag, text, parent = root) => {
    const node = document.createElement(tag); if (text) node.textContent = text;
    parent.append(node); return node;
  };
  const request = async (path, method = "GET", body) => {
    const headers = {"Content-Type": "application/json", Accept: "application/json"};
    if (platform === "shopify") headers.Authorization = `Bearer ${await window.shopify.idToken()}`;
    else headers["X-WP-Nonce"] = root.dataset.nonce;
    const response = await fetch(`${api}${path}`, {method, headers, credentials: "same-origin", body: body ? JSON.stringify(body) : undefined});
    if (response.status === 204) return {};
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || data.message || "Request failed");
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
    const a = el("a", "Continue to Lightek management", parent); a.className = "lc-link";
    a.href = url.href; a.target = "_blank"; a.rel = "noopener noreferrer";
    status.textContent = "Management link ready. It expires in 60 seconds.";
  };
  const shell = () => {root.replaceChildren(); el("h1", "Lightek Connect"); status = el("p", "", root); status.className = "lc-status"; status.setAttribute("role", "status");};
  const pairing = () => {
    shell(); el("p", "Create a connection code in your Lightek Dashboard → Lightek Connect, then paste it here.");
    const input = el("input"); input.type = "password"; input.autocomplete = "off"; input.placeholder = "Connection code"; input.setAttribute("aria-label", "Connection code");
    action("Connect agency", root, async () => {await request("/pair", "POST", {platform, code: input.value}); input.value = ""; await load();});
    const link = el("a", "Open Lightek Connect settings"); link.href = platform === "wordpress" ? root.dataset.origin + "/dashboard/connect" : "/dashboard/connect"; link.target = "_blank"; link.rel = "noopener noreferrer";
  };
  const load = async () => {
    const data = await request("/workspace"); shell(); el("p", `Connected to ${data.agency.name}`);
    const nav = el("div");
    data.capabilities.forEach(cap => action(cap.label, nav, async () => destination(await request("/dashboard", "POST", {path: cap.path}), nav)));
    const grid = el("div"); grid.className = "lc-grid";
    const sites = el("section", "", grid); el("h2", "Client websites", sites);
    if (!data.sites.length) el("p", "No client websites yet. Open Clients & agencies or Provision client hosting to get started.", sites);
    data.sites.forEach(site => {
      const row = el("article", "", sites); el("strong", site.name, row); el("small", site.host, row);
      action("Manage client instance", row, async () => destination(await request(`/sites/${site.id}/management`, "POST"), row));
      const name = el("input", "", row); name.value = site.name; name.maxLength = 160; name.setAttribute("aria-label", `Website name for ${site.host}`);
      action("Save website name", row, async () => {const saved = await request(`/sites/${site.id}`, "PATCH", {name: name.value}); status.textContent = saved.verified ? "Website name saved and verified." : "Save could not be verified.";});
    });
    const launches = el("section", "", grid); el("h2", "Recent deployments", launches);
    data.launches.forEach(launch => {const row = el("article", "", launches); el("strong", launch.name, row); el("small", `${launch.domain} · ${launch.status}`, row);});
    action("Refresh", root, load);
    action("Disconnect", root, async () => {await request("", "DELETE"); pairing();});
  };
  shell(); load().catch(() => pairing());
})();
