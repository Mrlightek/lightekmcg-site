# Blender modifier stack

Open a production’s native authoring workspace, select a mesh in the Outliner or viewport, then choose **Model → Modifier stack**. The stack follows Blender order, top to bottom. Changes are saved commands on the selected scene object; the library’s original `.blend` is unchanged.

## Add, adjust and review

1. In **Add modifier**, choose a type and a unique name. Set its type-specific values and apply. The request immediately saves one reversible edit; it does not start a final render.
2. Existing supported modifiers have their own parameter form. Adjust the desired fields and apply. Blank fields keep their worker value; they do not reset to zero. Imported projects prepared with older metadata may show unknown visibility or blank values until a worker refresh.
3. Use **Enable/Disable viewport** and **Enable/Disable render** independently. Viewport controls affect the Blender-generated GLB; render controls affect rendered frames. An off viewport with an on render can therefore show different geometry in the proxy and final picture.
4. Use **Move up/down** to change evaluation order, or **Remove** to remove the modifier from this production’s replayed copy. Unsupported native modifiers remain listed as read-only. Moving a supported modifier can move it across those entries without deleting or rewriting them.
5. Choose **Update Blender viewport** to obtain Blender’s authoritative geometry and parameter inventory. Use **Render this frame** to check the rendered result. Browser controls save intent; they do not pretend to simulate Blender’s evaluated modifier geometry locally.
6. **Undo/Redo** reverses saved commands, including removal and stack order. Save/export an editable Blender asset through the existing production workflow when needed. Final rendering/export retains its existing quote/checkout contract.

The default add name is only a starting point: choose a different unique name when it already exists. To change an existing modifier, use its stack card. Names must fit within 63 UTF-8 bytes. New modifiers are capped at 64 entries per object; existing larger imported stacks remain readable and supported entries remain adjustable. The existing 128-command/object bound and scene lock/version protections still apply.

## Supported parameters

| Modifier | Controls | Bounds |
| --- | --- | --- |
| Subdivision surface | Separate viewport and render levels | Whole levels 0–3 |
| Mirror | Clip mirror center | On/off; source axis/bisect settings remain intact |
| Solidify | Thickness in local object units | −100 to 100 |
| Bevel | Width in local units and segments | Width 0–100; whole segments 1–8 |
| Decimate | Remaining geometry ratio | 0.001–1 |

These controls preserve all other native settings. Rigs/Armature, Geometry Nodes and other modifier types stay in the stack as read-only entries. Existing exposed Geometry Nodes parameters and graph authoring remain separate controls. The stack does not destructively apply geometry, bake simulations, rename modifiers or author modifier animation curves.

Explicit parameter/visibility edits replace matching active Action curves and drivers on the copied object so those channels do not override a saved static setting at the rendered frame. Other animation channels are preserved. Advanced animation/NLA control remains separate work.

## Persistence and worker contract

The server validates type, named target, mesh eligibility, index, property bounds and boolean state before saving. It derives targets from the pinned native inventory and preceding saved commands, including authored Geometry Nodes entries. The browser never supplies arbitrary Blender property names, Python or operator strings. The command kinds are the existing `modifier` add/update and `modifier_state`, `modifier_move`, `modifier_remove` for stack edits.

Authoring GLB export evaluates modifiers for the static viewport proxy. This may flatten features such as shape keys in that proxy; the editable `.blend` is saved with its native stack/rig/shape-key source intact. Other GLB export workflows retain their existing settings.

Each worker rebuild starts from the pinned source, replays those commands once and returns an actual `modifier_stack` inventory alongside its normal mesh/graph metadata. A cached viewport is an evaluated snapshot; the UI projects only later command suffixes over it, or falls back to pinned-source projection when Undo crosses the snapshot. Reopening and template/episode reuse retain the ordinary scene-object command history. No schema migration is required.

Existing opened native projects retain their original inventory; a worker update supplies current parameter values for this page. Refreshing library metadata affects future openings without replacing an episode’s pinned source. The original file, unsupported native modifiers and rigs remain intact. Display changes do not auto-publish or start live output.

## Verification

Focused Rails checks cover target/type/state/index bounds, name/stack limits, stale writes, idempotency, undo/redo and manifest persistence. DOM checks cover typed parameters, source read-only entries, projected order/visibility, removal/undo, name collisions and worker snapshot suffix handling. Real Blender 4.3 checks import an animated/driven modifier, change its static parameters/order/flags, render a frame, export GLB and editable `.blend`, and reopen the output. The saved static override survives the evaluated frame; the base mesh remains editable and the original library blob is compared byte for byte.

These checks do not establish full modifier, rig, simulation or Blender/Maya parity. Integrated device/browser, shot and show acceptance remains in the final verification sprint. The implementation uses Blender’s [documented modifier collection API](https://docs.blender.org/api/4.0/bpy.types.ObjectModifiers.html).
