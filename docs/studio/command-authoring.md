# Controls → saved commands → Blender

Studio's native authoring API is the engine boundary. The browser edits a scene using supported data commands; Rails validates and saves them; Blender applies the same commands to the pinned native source when producing a viewport update, draft frame or final render. Slider movement does not start a render or checkout.

## Skew an object

Open Dashboard → Studio → a native production → Stage & FX. Select a mesh on the stage or in the scene list. **Skew object** appears in its ordinary object inspector and in the advanced Model tools.

Choose **Move axis** and a different **Along axis**. Drag **Skew amount**, or enter an exact amount between -2 and 2. The operation is an object-local shear around the object's origin: `position[move_axis] += amount * position[along_axis]`. An amount of 0.5 moves a point at Z=2 by X=1 for X-along-Z. Object rotation, placement and scale remain separate.

**Apply skew object** saves one reversible edit. **Reset preview** discards the unsaved adjustment. Undo and redo use the existing scene journal. Reopening a production replays its saved commands. A saved skew is additive; adjusting again starts a new operation, rather than silently rewriting history. Changing the selected object discards its pending preview.

Static meshes have an interactive Three.js geometry preview using the same local-coordinate equation as Blender. Earlier commands already baked into a Blender-generated GLB are not applied twice. Unsupported pending mesh operations, skinned/morph-target meshes, missing native proxies or zero-scale objects require **Update Blender viewport** for an accurate result; the control reports that requirement. It does not substitute a fake character or claim a bounds box is the rendered geometry.

The authoring panel uses Dashboard appearance variables, with the existing PWA palette as its standalone fallback. Imported artwork and rendered imagery retain their own colors.

## Engine contract

`studio.workspace.blender.authoring.edit` accepts the existing scene/object IDs, scene `lock_version`, unique `request_key`, `operation: "apply"`, and:

```json
{
  "kind": "mesh_skew",
  "axis": "X",
  "source_axis": "Z",
  "factor": 0.5,
  "indices": []
}
```

Empty indices mean the whole mesh. The API also supports the existing bounded explicit vertex selection. Axes must differ and factor must be finite within the permitted range. Existing scene ownership, request receipts, concurrency checks and the 128-edit per-object bound apply. Commands become part of the normal render manifest; no new executor, service, database table or migration is introduced.

`blender/authoring.py` applies the mesh operation. Shared mesh data is copied before editing, and every shape key receives the same linear transformation to preserve editable expressions. The original library `.blend` remains unchanged. The browser module `studio-mesh-commands.js` previews eligible static geometry in Blender object coordinates, including glTF axis conversion.

## Extend another engine operation

1. Select the documented engine operation and define its supported inputs, units, limits and output.
2. Add normalization to the existing API and dispatch to the engine adapter. Accept structured parameters rather than executable client scripts.
3. Connect the Lightek control to a local draft, then save once on Apply. Use an interactive preview when its result can faithfully match the operation; otherwise request an actual engine preview.
4. Verify saved/reopened source and produced media against the supplied values, along with undo, isolation and stale-save handling.

Use the same integration pattern for Blender deformation, rigs, compositor nodes, audio and model workflows. This change proves the skew workflow; it does not install Genesis models, add FL Studio feature parity or complete the wider media/live roadmap.

## Verification and deployment

Run the `StudioAuthoringTest` class in `test/standalone/studio_authoring_checks.rb` with `LIGHTEK_TEST_BLENDER=1` and `BLENDER_BIN` set. The skew test imports a real native source, saves the command through the application API, renders a PNG/GLB and editable `.blend`, reopens that `.blend` to inspect exact coordinates, and checks source immutability. The native-tools proof covers all six axis pairs, shared meshes and shape keys.

`studio_authoring_dom_test.cjs` checks preview/apply/reset, drafts and baked command prefixes; `studio_mesh_commands_test.cjs` checks actual Three.js geometry and coordinate conversion. `studio_authoring_test.cjs` checks browser interactions, layout and Dashboard palettes. DOM/geometry checks do not establish browser rendering acceptance. The dedicated command acceptance workflow also runs the real GLB viewport test.

Normal deployment must rebuild the media worker because its authoring Python changed, restart workers and refresh Studio assets. PWA shell cache advances to v66. No migration is required. The live production account workflow remains a deployment acceptance step.
