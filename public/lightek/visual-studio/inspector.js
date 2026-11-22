import { button, element, label, number, select } from "./dom.js";
import { VISEMES, transformAt } from "./scene-state.js";

function vector(name, value, change, scale = false) {
  return element("fieldset", { class: "vs-vector" }, element("legend", {}, name),
    ...value.map((component, index) => {
      const axis = ["X", "Y", "Z"][index];
      return label(axis, number(component, next => {
        const edited = value.slice();
        if (next === undefined) return;
        edited[index] = next;
        change(edited);
      }, { min: scale ? 0.001 : -3600, max: scale ? 100 : 3600, name: name + " " + axis }));
    }));
}

export function inspector(container, store, assets, actions, clips) {
  const layer = store.selected !== "camera";
  const value = store.channel;
  const current = transformAt(value, store.time);
  const content = [element("h3", {}, layer ? assets.get(value.asset_id)?.name ?? "Missing asset" : "Camera"),
    vector("Position", current.position, next => actions.transform("position", next)),
    vector("Rotation (°)", current.rotation, next => actions.transform("rotation", next))];
  if (!layer) {
    content.push(label("Lens (mm)", number(current.lens, next => actions.transform("lens", next), { min: 12, max: 100 })));
    container.replaceChildren(...content);
    return;
  }
  content.push(vector("Scale", current.scale, next => actions.transform("scale", next), true));
  const choices = [...assets.values()].filter(item => !["audio", "viseme"].includes(item.animation_role) &&
    (item.dimension_mode === value.dimension_mode || (value.dimension_mode === "2_5d" && item.dimension_mode === "2d")));
  content.push(label("Swap asset", select(choices.map(item => [item.id, item.name]), value.asset_id,
    id => actions.layer(item => { item.asset_id = Number(id); delete item.action; delete item.pose_frame; }))));
  if (assets.get(value.asset_id)?.dimension_mode === "2d") {
    content.push(label("Stage mode", select([["2d", "2D"], ["2_5d", "2.5D parallax"]], value.dimension_mode,
      mode => actions.layer(item => {
        item.dimension_mode = mode;
        if (mode === "2_5d") { item.z_depth = 0; item.relief = 0; }
        else { delete item.z_depth; delete item.relief; }
      }))));
  }
  content.push(label("Layer order", number(value.z_layer, next => actions.layer(item => { item.z_layer = next; }), { min: -100, max: 100, step: 1 })));
  if (value.dimension_mode === "2_5d") {
    content.push(label("Parallax depth", number(value.z_depth, next => actions.layer(item => { item.z_depth = next; }), { min: -5, max: 20 })),
      label("Relief", number(value.relief, next => actions.layer(item => { item.relief = next; }), { min: 0, max: 1 })));
  }
  if (value.dimension_mode === "3d") {
    const action = name => actions.layer(item => { if (name) item.action = name; else delete item.action; });
    if (clips.length) content.push(label("Model action", select([["", "Default"], ...new Set([...clips, value.action].filter(Boolean))].map(entry =>
      typeof entry === "string" ? [entry, entry] : entry), value.action, action)));
    else content.push(label("Native action name", element("input", { value: value.action, maxlength: 120, onchange: event => action(event.target.value.trim()) })));
    content.push(label("Freeze at model frame", number(value.pose_frame,
      next => actions.layer(item => { if (next === undefined) delete item.pose_frame; else item.pose_frame = next; }),
      { min: 0, max: 100000, step: 1 })));
    if (value.pose_frame !== undefined) content.push(button("Clear pose frame", () => actions.layer(item => { delete item.pose_frame; })));
  } else {
    const shapes = [...assets.values()].filter(item => item.animation_role === "viseme");
    const options = [["", "None"], ...shapes.map(item => [item.id, item.name])];
    const mouth = value.mouth;
    const editor = element("details", { open: !!mouth }, element("summary", {}, "Mouth artwork"),
      label("X · Rest", select(options, mouth?.variants.X, id => actions.layer(item => {
        if (!id) { delete item.mouth; return; }
        item.mouth ??= { position: [0, 0, 0], scale: [0.3, 0.3, 0.3], variants: {}, cues: [] };
        item.mouth.variants.X = Number(id);
      }))));
    if (mouth) {
      for (const shape of VISEMES.slice(1)) editor.append(label(shape, select(options, mouth.variants[shape],
        id => actions.layer(item => { if (id) item.mouth.variants[shape] = Number(id); else delete item.mouth.variants[shape]; }))));
      editor.append(vector("Mouth position", mouth.position, next => actions.layer(item => { item.mouth.position = next; })),
        vector("Mouth scale", mouth.scale, next => actions.layer(item => { item.mouth.scale = next; }), true));
    }
    content.push(editor);
  }
  content.push(button("Remove layer", actions.remove));
  container.replaceChildren(...content);
}
