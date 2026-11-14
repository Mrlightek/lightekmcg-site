/* Native authoring dock. Every edit is a saved command replayed by Blender. */
(() => {
  const ui = window.LightekStudioApp,
    esc = (v) => E(String(v ?? ""));
  const current = () => studioSceneRecord(studioCurrentSceneId());
  const selected = () => studioWorkspaceSelectedObject(current()?.scene);
  const state = {
    tab: "model",
    busy: false,
    message: "",
    selection: "",
    point: [0, 0, 0],
    frame: 1,
    playing: false,
    brush: false,
    skewDraft: null,
  };
  const previews = new Map();
  let playTimer = null,
    connection = null,
    lastScene = null;
  const call = async (action, payload) =>
    (
      await nevaeh.execute({
        capability: "studio.workspace.blender." + action,
        payload,
      })
    ).result;
  const run = (fn) =>
    Promise.resolve()
      .then(fn)
      .catch((e) => {
        state.message = e.message;
        toast(e.message);
        render(1);
      });
  const input = (key, label, value = 0, attrs = "") =>
    `<label class="fld"><span>${esc(label)}</span><input name="${key}" value="${esc(value)}" ${attrs}></label>`;
  const numeric = (key, label, value = 0, attrs = "") =>
    input(key, label, value, `type="number" step="any" ${attrs}`);
  const vector = (key, label, value = [0, 0, 0]) =>
    `<fieldset><legend>${esc(label)}</legend><div class="sa-vector">${["X", "Y", "Z"].map((axis, i) => numeric(`${key}_${i}`, axis, value[i])).join("")}</div></fieldset>`;
  const options = (values, selectedValue) =>
    values
      .map(
        (value) =>
          `<option ${value === selectedValue ? "selected" : ""}>${esc(value)}</option>`,
      )
      .join("");
  const toolForm = (kind, title, body) =>
    `<form data-authoring-form="${kind}"><h4>${title}</h4>${body}<button class="btn p sm" ${state.busy ? "disabled" : ""}>Apply ${title.toLowerCase()}</button></form>`;
  const selection = () =>
    input(
      "indices",
      "Element indices · blank selects all",
      state.selection,
      'placeholder="0, 1, 2"',
    );
  const frame = () =>
    numeric("frame", "Frame", state.frame, 'min="1" max="216000"');
  const graphScope = () =>
    `<label class="fld"><span>Graph</span><select name="scope">${options(["material", "geometry", "compositor"], "material")}</select></label>${numeric("slot", "Material slot", 0, 'min="0" max="63"')}${input("modifier", "Geometry modifier", "Studio Geometry")}`;
  const nodes = {
    material: [
      "ShaderNodeBsdfPrincipled",
      "ShaderNodeOutputMaterial",
      "ShaderNodeTexNoise",
      "ShaderNodeTexVoronoi",
      "ShaderNodeTexChecker",
      "ShaderNodeTexCoord",
      "ShaderNodeMapping",
      "ShaderNodeValToRGB",
      "ShaderNodeMixRGB",
      "ShaderNodeMath",
      "ShaderNodeBump",
      "ShaderNodeNormalMap",
      "ShaderNodeEmission",
      "ShaderNodeMixShader",
      "ShaderNodeBsdfTransparent",
      "ShaderNodeRGB",
      "ShaderNodeValue",
    ],
    geometry: [
      "NodeGroupInput",
      "NodeGroupOutput",
      "GeometryNodeTransform",
      "GeometryNodeMeshCube",
      "GeometryNodeMeshUVSphere",
      "GeometryNodeSetPosition",
      "GeometryNodeInputPosition",
      "GeometryNodeJoinGeometry",
      "GeometryNodeSubdivisionSurface",
      "GeometryNodeSetMaterial",
      "GeometryNodeInstanceOnPoints",
      "GeometryNodeRealizeInstances",
      "GeometryNodeDistributePointsOnFaces",
      "ShaderNodeMath",
      "ShaderNodeVectorMath",
      "ShaderNodeTexNoise",
      "ShaderNodeValue",
    ],
    compositor: [
      "CompositorNodeRLayers",
      "CompositorNodeComposite",
      "CompositorNodeGlare",
      "CompositorNodeBlur",
      "CompositorNodeMixRGB",
      "CompositorNodeColorBalance",
      "CompositorNodeLensdist",
      "CompositorNodeAlphaOver",
      "CompositorNodeBrightContrast",
      "CompositorNodeHueSat",
      "CompositorNodeRGB",
      "CompositorNodeValue",
    ],
  };
  function skewControls(object = selected()) {
    const d = object?.definition || {}, draft = state.skewDraft;
    const hasDraft = draft?.objectId === object?.id && draft.sceneId === current()?.scene.id;
    const skew = hasDraft ? draft.command : { axis: "X", source_axis: "Z", factor: 0 };
    const mesh = ["MESH", "CUBE", "SPHERE", "CYLINDER", "PLANE"].includes(d.native_type || object?.object_type?.toUpperCase());
    return mesh && !d.native_source_preview ? toolForm(
        "mesh_skew", "Skew object",
        `<p>Lean the mesh around its local origin. Drag to preview, then apply to save.</p><label class="fld"><span>Move axis</span><select name="axis">${options(["X", "Y", "Z"], skew.axis)}</select></label><label class="fld"><span>Along axis</span><select name="source_axis">${options(["X", "Y", "Z"], skew.source_axis)}</select></label><label class="fld"><span>Skew amount</span><input name="factor" type="range" min="-2" max="2" step="0.01" value="${skew.factor}"></label><label class="fld"><span>Exact amount</span><input name="factor_value" type="number" min="-2" max="2" step="0.01" value="${skew.factor}"></label><button type="button" class="btn sm" data-a="studioAuthorSkewReset">Reset preview</button><p data-skew-status role="status">${hasDraft ? "Preview changes are unsaved." : "Adjust to preview. Apply saves one edit."}</p>`,
      ) : "";
  }
  ui.objectControls = object => {
    const control = skewControls(object);
    return control ? `<div class="sa-dock sa-object-controls"><div class="sa-form-grid">${control}</div><div class="pwa-post-actions"><button class="btn sm" data-a="studioAuthorUndo">Undo</button><button class="btn sm" data-a="studioAuthorRedo">Redo</button><button class="btn sm" data-a="studioAuthorSync">Update Blender viewport</button></div></div>` : "";
  };
  function model(d) {
    return (
      skewControls() +
      toolForm(
        "mesh_translate",
        "Move vertices",
        selection() + vector("delta", "Move by"),
      ) +
      toolForm(
        "mesh_extrude",
        "Extrude faces",
        selection() + vector("delta", "Extrusion", [0, 0, 0.2]),
      ) +
      toolForm(
        "mesh_subdivide",
        "Subdivide edges",
        selection() + numeric("cuts", "Cuts", 1, 'min="1" max="4"'),
      ) +
      toolForm(
        "mesh_inset",
        "Inset faces",
        selection() + numeric("amount", "Thickness", 0.1),
      ) +
      toolForm(
        "mesh_bevel",
        "Bevel edges",
        selection() +
          numeric("amount", "Width", 0.1) +
          numeric("segments", "Segments", 2, 'min="1" max="8"'),
      ) +
      toolForm("mesh_delete", "Delete faces", selection()) +
      toolForm(
        "mesh_merge",
        "Merge vertices",
        selection() + numeric("amount", "Merge distance", 0.001),
      ) +
      toolForm(
        "modifier",
        "Modifier",
        input("name", "Modifier name", "Studio Subdivision") +
          `<label class="fld"><span>Type</span><select name="type">${options(["SUBSURF", "MIRROR", "SOLIDIFY", "BEVEL", "DECIMATE"], "SUBSURF")}</select></label>` +
          numeric("amount", "Level / thickness / ratio", 1),
      ) +
      (d.mesh
        ? `<details class="sa-topology"><summary>Mesh topology · ${d.mesh.vertex_count} vertices / ${d.mesh.face_count} faces</summary><p>${d.mesh.sampled ? "First 4096 elements shown. Brush strokes affect the mesh within the selected radius." : ""}</p><div>${d.mesh.vertices
            .slice(0, 300)
            .map(
              (v) =>
                `<button class="btn sm" data-a="studioAuthorVertex" data-index="${v[0]}" data-point="${esc(v.slice(1).join(","))}">V${v[0]} · ${v
                  .slice(1)
                  .map((n) => Number(n).toFixed(2))
                  .join(", ")}</button>`,
            )
            .join("")}</div><p>Faces: ${d.mesh.faces
            .slice(0, 60)
            .map((f) => `${f[0]} (${f.slice(1).join(",")})`)
            .join(" · ")}</p></details>`
        : "")
    );
  }
  function sculpt() {
    return (
      toolForm(
        "sculpt",
        "Sculpt stroke",
        `<button type="button" class="btn sm" data-a="studioAuthorBrush" aria-pressed="${state.brush}">${state.brush ? "Disable paint brush" : "Paint directly on mesh"}</button>` +
          `<p>Click the mesh in the viewport to place the brush, then apply a stroke. Coordinates are in the object’s local space.</p>` +
          vector("center", "Brush center", state.point) +
          numeric("radius", "Brush radius", 0.5, 'min="0.001"') +
          vector("delta", "Brush displacement", [0, 0, 0.1]),
      ) +
      toolForm(
        "mesh_smooth",
        "Smooth vertices",
        selection() +
          numeric("amount", "Strength", 0.5, 'min="0" max="1"') +
          numeric("iterations", "Passes", 1, 'min="1" max="10"'),
      )
    );
  }
  function rig(d) {
    const bones = d.bones || [];
    return (
      `<section><h4>Rig hierarchy</h4><div class="sa-bones">${bones.map((b) => `<span>${esc(b.name)}${b.parent ? " ← " + esc(b.parent) : ""}</span>`).join("") || "Select an armature in the Outliner to pose its bones."}</div></section>` +
      toolForm(
        "bone_pose",
        "Bone pose",
        `<label class="fld"><span>Bone</span><select name="bone">${options(bones.map((b) => b.name))}</select></label>` +
          vector("location", "Location") +
          vector("rotation", "Rotation · degrees") +
          vector("scale", "Scale", [1, 1, 1]) +
          frame(),
      ) +
      toolForm(
        "bone_add",
        "Add bone",
        input("name", "Bone name", "New control") +
          input("parent", "Parent bone · optional") +
          vector("head", "Head") +
          vector("tail", "Tail", [0, 0, 1]),
      ) +
      toolForm(
        "weight",
        "Vertex weights",
        selection() +
          input(
            "group",
            "Vertex group / bone",
            d.vertex_groups?.[0] || "Bone",
          ) +
          numeric("weight", "Weight", 1, 'min="0" max="1"'),
      ) +
      ((d.shape_keys || []).length
        ? toolForm(
            "shape_key",
            "Shape key",
            `<label class="fld"><span>Shape</span><select name="name">${options(d.shape_keys.map((k) => k.name))}</select></label>` +
              numeric("value", "Value", 0) +
              frame(),
          )
        : "")
    );
  }
  function animate(d) {
    return (
      toolForm(
        "keyframe",
        "Transform keyframe",
        frame() +
          vector("location", "Location", d.location) +
          vector("rotation", "Rotation · degrees", d.rotation) +
          vector("scale", "Scale", d.scale || [1, 1, 1]),
      ) +
      `<section><h4>Animation tracks</h4><p>Original Blender actions, armatures, constraints, modifiers and imported animation stay in the native source. Saved keyframes override the chosen channels at their frames.</p><div class="sa-keys">${(current()?.scene.objects || []).flatMap((o) => (o.definition.authoring_commands || []).filter((c) => c.frame).map((c) => `<button class="btn sm" data-a="studioAuthorFrame" data-frame="${c.frame}">${esc(o.name)} · ${c.bone ? esc(c.bone) + " · " : ""}${c.frame}</button>`)).join("") || "No new keyframes yet."}</div><button class="btn" data-a="studioAuthorMovie">Export movie shot</button></section>`
    );
  }
  function graphView(d) {
    const graphs = [
      ...(d.graphs || []),
      ...(current()?.scene.settings?.compositor_graph
        ? [
            {
              scope: "compositor",
              graph: current().scene.settings.compositor_graph,
            },
          ]
        : []),
    ];
    return graphs
      .map((g) => {
        const graph = g.graph;
        if (!graph) return "";
        const nodes = graph.nodes || [],
          positions = new Map(
            nodes.map((n, i) => [
              n.name,
              { x: 25 + (i % 4) * 205, y: 35 + Math.floor(i / 4) * 155 },
            ]),
          );
        return `<section class="sa-graph" data-graph-scope="${esc(g.scope)}" data-graph-slot="${g.slot || 0}" data-graph-modifier="${esc(g.modifier || "Studio Geometry")}"><h4>${esc(g.scope)} · ${esc(graph.name)}${g.modifier ? " · " + esc(g.modifier) : ""}</h4><p>Click an output socket, then an input socket to connect them.</p><svg viewBox="0 0 850 ${Math.max(200, Math.ceil(nodes.length / 4) * 155 + 40)}" role="img" aria-label="${esc(g.scope)} node connections">${(
          graph.links || []
        )
          .map((l) => {
            const a = positions.get(l.from),
              b = positions.get(l.to);
            return a && b
              ? `<path d="M${a.x + 180},${a.y + 50} C${a.x + 230},${a.y + 50} ${b.x - 50},${b.y + 50} ${b.x},${b.y + 50}" fill="none" stroke="#c4aa75" stroke-width="2"/>`
              : "";
          })
          .join("")}${nodes
          .map((n) => {
            const p = positions.get(n.name);
            return `<g transform="translate(${p.x} ${p.y})"><rect width="180" height="125" rx="8" fill="#1d2b38" stroke="#52667a"/><text x="10" y="23" fill="#fff" font-size="12">${esc(n.name.slice(0, 24))}</text><text x="10" y="44" fill="#c4aa75" font-size="9">${esc(n.type.slice(0, 29))}</text>${n.inputs
              .slice(0, 3)
              .map(
                (s, i) =>
                  `<text x="10" y="${65 + i * 17}" fill="#b0c5d5" font-size="10">${s.index}: ${esc(s.name.slice(0, 22))}</text>`,
              )
              .join("")}${n.inputs
              .slice(0, 3)
              .map(
                (socket, i) =>
                  `<circle cy="${62 + i * 17}" r="6" fill="#96d6d0" role="button" tabindex="0" aria-label="Connect input ${esc(n.name)} ${socket.index}" data-graph-port="input" data-node="${esc(n.name)}" data-index="${socket.index}"/>`,
              )
              .join("")}${n.outputs
              .slice(0, 3)
              .map(
                (socket, i) =>
                  `<circle cx="180" cy="${62 + i * 17}" r="6" fill="#c4aa75" role="button" tabindex="0" aria-label="Select output ${esc(n.name)} ${socket.index}" data-graph-port="output" data-node="${esc(n.name)}" data-index="${socket.index}"/>`,
              )
              .join("")}</g>`;
          })
          .join(
            "",
          )}</svg><details><summary>Socket names and indices</summary>${nodes.map((n) => `<p><b>${esc(n.name)}</b> · inputs ${n.inputs.map((s) => `${s.index}: ${esc(s.name)}`).join(" / ")} · outputs ${n.outputs.map((s) => `${s.index}: ${esc(s.name)}`).join(" / ")}</p>`).join("")}</details></section>`;
      })
      .join("");
  }
  function nodeForms(d) {
    return (
      `<div class="sa-node-graphs">${graphView(d) || "<p>Choose a material graph or add a Geometry Nodes modifier.</p>"}</div>` +
      toolForm(
        "node_add",
        "Add node",
        graphScope() +
          input("name", "Node name", "Studio Node") +
          `<label class="fld"><span>Node type</span><select name="type">${options(nodes.material)}</select></label>`,
      ) +
      toolForm(
        "node_link",
        "Connect sockets",
        graphScope() +
          input("from", "Output node name") +
          numeric("output", "Output socket index", 0) +
          input("to", "Input node name") +
          numeric("input", "Input socket index", 0),
      ) +
      toolForm(
        "node_value",
        "Socket value",
        graphScope() +
          input("name", "Node name") +
          numeric("input", "Input socket index", 0) +
          input("value", "Number or comma-separated vector", "0.5"),
      ) +
      toolForm(
        "node_remove",
        "Remove node",
        graphScope() + input("name", "Node name"),
      )
    );
  }
  const tools = ui.tools;
  ui.tools = (record) => {
    const object = studioWorkspaceSelectedObject(record.scene),
      d = object?.definition || {};
    return (
      tools(record) +
      `<section class="sa-dock" aria-label="Native production authoring"><header><div><span class="eb">PRODUCTION AUTHORING</span><h3>${esc(object?.name || "Select a scene element")}</h3></div><div class="pwa-post-actions"><button class="btn sm" data-a="studioAuthorUndo" ${state.busy ? "disabled" : ""}>Undo</button><button class="btn sm" data-a="studioAuthorRedo" ${state.busy ? "disabled" : ""}>Redo</button><button class="btn p sm" data-a="studioAuthorSync" ${state.busy ? "disabled" : ""}>Update Blender viewport</button></div></header><nav aria-label="Authoring tools">${["model", "sculpt", "rig", "animate", "nodes"].map((tab) => `<button class="btn sm ${state.tab === tab ? "p" : ""}" data-a="studioAuthorTab" data-tab="${tab}" aria-pressed="${state.tab === tab}">${tab === "model" ? "Model" : tab === "sculpt" ? "Sculpt" : tab === "rig" ? "Rig & weights" : tab === "animate" ? "Animate" : "Node graphs"}</button>`).join("")}</nav><div class="sa-transport"><button class="btn sm" data-a="studioAuthorPlay">${state.playing ? "Pause" : "Play preview"}</button><label>Frame <input data-authoring-frame type="range" min="${record.scene.settings.frame_start || 1}" max="${record.scene.settings.frame_end || 250}" value="${state.frame}"></label><output data-authoring-frame-label>${state.frame}</output><button class="btn sm" data-a="studioAuthorRenderFrame">Render this frame</button></div><p role="status" data-authoring-status>${esc(state.message || "Edits stay reversible. Update the Blender viewport to see the saved mesh, rig and graph result.")}</p>${object && !d.native_source_preview ? `<details class="sa-tools" open><summary>${esc(state.tab)} tools · ${d.authoring_commands?.length || 0} saved edits</summary><div class="sa-form-grid">${state.tab === "model" ? model(d) : state.tab === "sculpt" ? sculpt() : state.tab === "rig" ? rig(d) : state.tab === "animate" ? animate(d) : nodeForms(d)}</div></details>` : "<p>Select an object in the 3D view or Blender Outliner. Upload .blend files or resource ZIPs in the asset browser.</p>"}${previews.get(record.scene.id)?.image ? `<img class="sa-render" src="${esc(previews.get(record.scene.id).image)}" alt="Authoritative Blender authoring render">` : ""}</section>`
    );
  };
  A.studioAuthorTab = (b) => {
    clearSkewDraft();
    state.tab = b.dataset.tab;
    render(1);
  };
  A.studioAuthorVertex = (b) => {
    state.selection = b.dataset.index;
    state.point = b.dataset.point.split(",").map(Number);
    render(1);
  };
  A.studioAuthorFrame = (b) => {
    state.frame = Number(b.dataset.frame);
    dispatchFrame();
    render(1);
  };
  const dispatchFrame = () =>
    window.dispatchEvent(
      new CustomEvent("lightek:authoring-frame", {
        detail: { sceneId: current()?.scene.id, frame: state.frame },
      }),
    );
  A.studioAuthorPlay = () => {
    state.playing = !state.playing;
    clearInterval(playTimer);
    if (state.playing)
      playTimer = setInterval(
        () => {
          const scene = current()?.scene;
          if (!scene || !location.hash.startsWith("#/studio/")) {
            clearInterval(playTimer);
            state.playing = false;
            return;
          }
          state.frame =
            state.frame >= Number(scene.settings.frame_end || 250)
              ? Number(scene.settings.frame_start || 1)
              : state.frame + 1;
          dispatchFrame();
          const slider = app.querySelector("[data-authoring-frame]");
          if (slider) slider.value = state.frame;
          const label = app.querySelector("[data-authoring-frame-label]");
          if (label) label.textContent = state.frame;
        },
        1000 / Number(current()?.scene.settings.fps || 24),
      );
    render(1);
  };
  async function edit(operation, command) {
    if (state.busy) return;
    const record = current(),
      object = selected();
    if (!record || (operation === "apply" && !object))
      throw Error("Select an editable object.");
    state.busy = true;
    try {
      const result = await call("authoring.edit", {
        scene_id: record.scene.id,
        object_id: object?.id,
        lock_version: record.scene.lock_version,
        operation,
        command,
        request_key: crypto.randomUUID(),
      });
      clearSkewDraft();
      await A.studioLoad(true);
      ST.selectedObjectId = result.object_id;
      state.message =
        "Edit saved. Update Blender viewport to inspect the result.";
    } finally {
      state.busy = false;
      render(1);
    }
  }
  A.studioAuthorBrush = () => {
    state.brush = !state.brush;
    state.message = state.brush
      ? "Drag across the selected mesh to sculpt. Each stroke saves an undoable edit."
      : "Paint brush disabled.";
    render(1);
  };
  window.LightekStudioBrush = {
    get active() {
      return state.brush && state.tab === "sculpt" && !state.busy;
    },
    settings() {
      const f = app.querySelector('[data-authoring-form="sculpt"]')?.elements;
      return f
        ? {
            radius: Number(f.radius.value),
            delta: [0, 1, 2].map((i) => Number(f[`delta_${i}`].value)),
          }
        : null;
    },
    commit(objectId, points) {
      if (!points.length || objectId !== selected()?.id) return;
      const settings = this.settings();
      if (settings)
        run(() =>
          edit("apply", {
            kind: "sculpt",
            center: points[0],
            path: points.slice(1, 32),
            ...settings,
          }),
        );
    },
  };
  A.studioAuthorUndo = () => run(() => edit("undo"));
  A.studioAuthorRedo = () => run(() => edit("redo"));
  function clearSkewDraft() {
    state.skewDraft = null;
    window.dispatchEvent(new CustomEvent("lightek:mesh-command-preview", {
      detail: { sceneId: current()?.scene.id, objectId: selected()?.id },
    }));
  }
  window.LightekStudioMeshDraft = () => {
    const draft = state.skewDraft;
    return draft && state.tab === "model" && draft.sceneId === current()?.scene.id && draft.objectId === selected()?.id ? draft : null;
  };
  A.studioAuthorSkewReset = () => {
    clearSkewDraft();
    render(1);
  };
  app.addEventListener("input", event => {
    const form = event.target.closest('[data-authoring-form="mesh_skew"]');
    if (!form || state.busy) return;
    const f = form.elements;
    if (event.target.name === "factor_value") f.factor.value = f.factor_value.value;
    else f.factor_value.value = f.factor.value;
    const command = { kind: "mesh_skew", axis: f.axis.value, source_axis: f.source_axis.value, factor: Number(f.factor_value.value), indices: [] };
    f.source_axis.setCustomValidity(command.axis === command.source_axis ? "Choose two different axes." : "");
    if (!form.checkValidity()) return;
    state.tab = "model";
    state.skewDraft = { sceneId: current()?.scene.id, objectId: selected()?.id, command };
    window.dispatchEvent(new CustomEvent("lightek:mesh-command-preview", { detail: state.skewDraft }));
  });
  window.addEventListener("lightek:mesh-command-preview-status", event => {
    if (event.detail?.sceneId !== current()?.scene.id || event.detail?.objectId !== selected()?.id) return;
    const status = app.querySelector("[data-skew-status]");
    if (status) status.textContent = event.detail.ok ? (window.LightekStudioMeshDraft() ? "Live preview · Apply skew object to save." : "Saved mesh preview. Adjust to add another skew, or Undo.") : event.detail.reason;
  });
  window.addEventListener("lightek:visual-selection", () => {
    if (state.skewDraft && state.skewDraft.objectId !== selected()?.id) clearSkewDraft();
  });
  A.studioAuthorRenderFrame = () => {
    const input = app.querySelector("[data-blender-preview-frame]");
    if (input) input.value = state.frame;
    return A.studioBlenderDraftPreview();
  };
  A.studioAuthorMovie = () =>
    run(async () => {
      const result = await nevaeh.execute({
        capability: "studio.workspace.render.quote",
        payload: { scene_id: current().scene.id, output: "movie" },
      });
      ui.setQuote(result.result);
      if(window.LightekStudioProduction)LightekStudioProduction.go("deliver",undefined,true);
      else{ST.workspaceMode = "publish";render(1);}
    });
  A.studioAuthorSync = () =>
    run(async () => {
      if (state.busy) return;
      const record = current();
      if (!record) return;
      state.busy = true;
      state.message = "Blender is rebuilding the edited viewport…";
      render(1);
      try {
        let result = await call("authoring.preview", {
          scene_id: record.scene.id,
          object_id: selected()?.id,
          frame: state.frame,
        });
        const id = record.scene.id;
        for (
          let attempt = 0;
          ["pending", "running"].includes(result.status) && attempt < 60;
          attempt++
        ) {
          await new Promise((resolve) => setTimeout(resolve, 2000));
          result = await call("authoring.preview", {
            scene_id: id,
            operation_id: result.operation_id,
          });
        }
        if (result.status !== "completed")
          throw Error(
            result.error ||
              "The Blender preview is still processing; check Studio operations.",
          );
        const fresh = studioSceneRecord(id);
        if (
          Number(fresh?.scene.settings.native_revision || 0) !==
          Number(result.native_revision || 0)
        )
          throw Error("A newer edit exists. Update the viewport again.");
        previews.set(id, {
          revision: result.native_revision,
          proxy: result.proxy_url,
          image: result.url,
          inventory: result.authoring,
          commands: Object.fromEntries((fresh.scene.objects || []).map(o => [o.id, structuredClone(o.definition.authoring_commands || [])])),
          transforms: Object.fromEntries((fresh.scene.objects || []).map(o => [o.id, structuredClone({ location:o.definition.location, rotation:o.definition.rotation, scale:o.definition.scale })])),
        });
        mergeInventory(fresh);
        state.message = "Blender viewport and object metadata updated.";
      } finally {
        state.busy = false;
        render(1);
      }
    });
  function mergeInventory(record) {
    const cache = previews.get(record.scene.id);
    if (
      !cache ||
      Number(cache.revision || 0) !==
        Number(record.scene.settings.native_revision || 0)
    )
      return;
    for (const object of record.scene.objects || [])
      if (cache.inventory?.[object.id])
        Object.assign(object.definition, cache.inventory[object.id]);
  }
  const prepare = ui.prepare;
  ui.prepare = (record) => {
    prepare(record);
    if (state.skewDraft && (state.skewDraft.sceneId !== record.scene.id || state.skewDraft.objectId !== selected()?.id)) clearSkewDraft();
    if (lastScene !== record.scene.id) {
      lastScene = record.scene.id;
      state.frame = Number(record.scene.settings.frame_current || 1);
      state.brush = false;
      state.playing = false;
      clearInterval(playTimer);
    }
    mergeInventory(record);
  };
  const snapshot = window.LightekStudioViewportBridge?.snapshot;
  if (snapshot)
    LightekStudioViewportBridge.snapshot = () => {
      const data = snapshot(),
        cache = data && previews.get(data.sceneId);
      if (!data) return data;
      const scene = current()?.scene;
      if (
        !cache?.proxy ||
        !(scene?.objects || []).every(o => {
          const baked = cache.commands?.[o.id] || [], saved = o.definition.authoring_commands || [];
          return baked.length <= saved.length && JSON.stringify(baked) === JSON.stringify(saved.slice(0, baked.length));
        })
      )
        return data;
      let found = false;
      const objects = data.objects.map((o) => {
        if (!o.definition?.native_source_preview) return { ...o, definition: { ...o.definition, viewport_baked_commands: cache.commands?.[o.id] || [], viewport_source_transform:cache.transforms?.[o.id] } };
        found = true;
        return {
          ...o,
          definition: { ...o.definition, asset_proxy_url: cache.proxy },
        };
      });
      if (!found)
        objects.push({
          id: -Number(scene.id),
          object_type: "imported_asset",
          name: "Edited Blender preview",
          definition: {
            native_source_preview: true,
            asset_proxy_url: cache.proxy,
            location: [0, 0, 0],
            rotation: [0, 0, 0],
            scale: [1, 1, 1],
          },
        });
      return { ...data, objects };
    };
  app.addEventListener("change", (event) => {
    if (event.target.matches("[data-authoring-frame]")) {
      state.frame = Number(event.target.value);
      dispatchFrame();
      const label = app.querySelector("[data-authoring-frame-label]");
      if (label) label.textContent = state.frame;
    }
    if (
      event.target.name === "scope" &&
      event.target.closest('[data-authoring-form="node_add"]')
    )
      event.target.form.elements.type.innerHTML = options(
        nodes[event.target.value],
      );
  });
  window.addEventListener("lightek:authoring-pick", (event) => {
    if (event.detail?.sceneId !== current()?.scene.id) return;
    state.point = event.detail.point;
    const form = app.querySelector('[data-authoring-form="sculpt"]');
    if (form)
      [0, 1, 2].forEach(
        (i) => (form.elements[`center_${i}`].value = state.point[i].toFixed(4)),
      );
  });
  app.addEventListener("click", (event) => {
    const port = event.target.closest("[data-graph-port]");
    if (!port) return;
    const graph = port.closest("[data-graph-scope]"),
      scope = graph.dataset.graphScope,
      slot = Number(graph.dataset.graphSlot),
      modifier = graph.dataset.graphModifier;
    if (port.dataset.graphPort === "output") {
      connection = {
        scope,
        slot,
        modifier,
        from: port.dataset.node,
        output: Number(port.dataset.index),
      };
      state.message = "Now select the input socket.";
      app.querySelector("[data-authoring-status]").textContent = state.message;
    } else if (
      connection &&
      connection.scope === scope &&
      connection.slot === slot &&
      connection.modifier === modifier
    ) {
      const command = {
        kind: "node_link",
        ...connection,
        to: port.dataset.node,
        input: Number(port.dataset.index),
      };
      connection = null;
      run(() => edit("apply", command));
    } else toast("Choose an output socket from this graph first.");
  });
  app.addEventListener("keydown", (event) => {
    if (
      event.target.matches("[data-graph-port]") &&
      ["Enter", " "].includes(event.key)
    ) {
      event.preventDefault();
      event.target.dispatchEvent(new MouseEvent("click", { bubbles: true }));
    }
  });
  app.addEventListener("submit", (event) => {
    const form = event.target.closest("[data-authoring-form]");
    if (!form) return;
    event.preventDefault();
    run(async () => {
      const f = form.elements,
        kind = form.dataset.authoringForm,
        cmd = { kind };
      const num = (name) => Number(f[name].value);
      const vec = (name) => [0, 1, 2].map((i) => num(`${name}_${i}`));
      if (f.indices)
        cmd.indices = f.indices.value.trim()
          ? f.indices.value.split(/[\s,]+/).map(Number)
          : [];
      if (f.delta) {
      }
      if (f.delta_0) cmd.delta = vec("delta");
      if (f.amount) cmd.amount = num("amount");
      for (const key of [
        "cuts",
        "segments",
        "iterations",
        "radius",
        "frame",
        "weight",
      ])
        if (f[key]) cmd[key] = num(key);
      if (kind === "sculpt") cmd.center = vec("center");
      if (kind === "mesh_skew") {
        cmd.axis = f.axis.value;
        cmd.source_axis = f.source_axis.value;
        cmd.factor = num("factor_value");
        cmd.indices = [];
      }
      if (["bone_pose", "keyframe"].includes(kind))
        for (const key of ["location", "rotation", "scale"])
          cmd[key] = vec(key);
      if (kind === "bone_pose") cmd.bone = f.bone.value;
      if (kind === "bone_add") {
        cmd.head = vec("head");
        cmd.tail = vec("tail");
        cmd.parent = f.parent.value;
      }
      if (f.group) cmd.group = f.group.value;
      if (f.name) cmd.name = f.name.value;
      if (kind === "shape_key") cmd.value = num("value");
      if (kind === "modifier") {
        cmd.type = f.type.value;
        cmd.properties =
          cmd.type === "SUBSURF"
            ? { levels: num("amount"), render_levels: num("amount") }
            : cmd.type === "SOLIDIFY"
              ? { thickness: num("amount") }
              : cmd.type === "DECIMATE"
                ? { ratio: num("amount") }
                : cmd.type === "BEVEL"
                  ? { width: num("amount"), segments: 2 }
                  : { use_clip: true };
        delete cmd.amount;
      }
      if (kind.startsWith("node_")) {
        cmd.scope = f.scope.value;
        cmd.slot = num("slot");
        cmd.modifier = f.modifier.value;
        if (f.type) cmd.type = f.type.value;
        for (const key of ["from", "to"]) if (f[key]) cmd[key] = f[key].value;
        for (const key of ["input", "output"]) if (f[key]) cmd[key] = num(key);
        if (kind === "node_value") {
          const value = f.value.value;
          cmd.value =
            value === "true"
              ? true
              : value === "false"
                ? false
                : value.includes(",")
                  ? value.split(",").map(Number)
                  : Number(value);
        }
      }
      await edit("apply", cmd);
    });
  });
})();
