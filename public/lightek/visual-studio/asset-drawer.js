import { button, element, label, select } from "./dom.js";

const roles = [["character", "Character"], ["prop", "Prop"], ["background", "Background"], ["audio", "Audio"], ["viseme", "Mouth artwork"]];
const dimensions = [["2d", "2D"], ["2_5d", "2.5D"], ["3d", "3D"]];

export function assetDrawer(container, assets, actions) {
  const search = element("input", { type: "search", placeholder: "Search assets", "aria-label": "Search assets" });
  const list = element("ul", { class: "vs-asset-list" });
  const update = () => {
    const term = search.value.toLowerCase();
    const matches = [...assets.values()].filter(item => item.name.toLowerCase().includes(term));
    list.replaceChildren(...matches.map(asset => {
      const row = element("li", {}, element("strong", {}, asset.name),
        element("small", {}, asset.starter ? "Character Builder starter" : [asset.animation_role, asset.dimension_mode].filter(Boolean).join(" · ")));
      if (asset.animation_role !== "viseme") {
        const audio = asset.animation_role === "audio";
        row.append(button(audio ? "Use audio" : "Add layer", () => audio ? actions.audio(asset.id) : actions.add(asset)));
      }
      if (asset.preview_request_url && !asset.preview_url) {
        row.append(button(asset.preview_status === "queued" ? "Preview queued" : "Build model preview",
          () => actions.preview(asset), { disabled: asset.preview_status === "queued" }));
      }
      if (!asset.starter) row.append(button("Manage", () => actions.manage(asset)));
      return row;
    }));
    if (!matches.length) list.append(element("li", {}, term ? "No matching assets." : "Upload an asset or build a starter in Character Builder."));
  };
  search.addEventListener("input", update);
  const upload = element("details", {}, element("summary", {}, "Upload asset"), assetForm(null, actions));
  container.replaceChildren(upload, search, list);
  update();
}

export function assetForm(asset, actions) {
  const name = element("input", { name: "asset[name]", required: true, maxlength: 160, value: asset?.name ?? "" });
  const mode = select(dimensions, asset?.dimension_mode ?? "2d", () => {});
  mode.name = "asset[dimension_mode]";
  const role = select(roles, asset?.animation_role ?? "character", () => syncRole());
  role.name = "asset[animation_role]";
  const file = element("input", { name: "asset[file]", type: "file", required: !asset });
  const syncRole = () => {
    mode.disabled = ["audio", "viseme"].includes(role.value);
    file.accept = role.value === "audio" ? ".wav,.mp3,.m4a,.aac,.ogg,.flac" :
      mode.value === "3d" && role.value !== "viseme" ? ".glb,.gltf,.fbx,.blend" : ".png,.webp,.svg";
  };
  mode.addEventListener("change", syncRole);
  const form = element("form", { class: "vs-asset-form", onsubmit: async event => {
    event.preventDefault();
    const fields = new FormData(form);
    if (!file.files.length) fields.delete("asset[file]");
    const result = await actions.saveAsset(asset, fields);
    if (result && !asset) { form.reset(); syncRole(); }
  } }, label("Name", name), label("Type", role), label("Dimensions", mode),
  label(asset ? "Replace file" : "File", file), element("button", { type: "submit" }, asset ? "Save asset" : "Upload"));
  if (asset) form.append(button("Delete asset", () => actions.deleteAsset(asset)));
  syncRole();
  return form;
}
