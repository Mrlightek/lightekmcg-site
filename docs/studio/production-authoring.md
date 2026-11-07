# Native production authoring and virtual stages

The Studio workflow is now **import → author → animate → render → publish or broadcast**. Blender is the native engine. No Tripo credential is required for these workflows.

## Import and preserve

Import standalone `.blend` files (including compressed Blender files), GLB models, or Blender resource ZIPs. ZIP extraction rejects traversal and symlinks, caps expanded data at 2 GB, and accepts up to 20 Blender projects. Individual files in a package become independent library entries, retaining the resource archive and relative source path. Uploads retain the existing 250 MB limit.

Preparation records mesh topology samples, rig bones and parents, vertex groups, shape keys, material and Geometry Nodes graphs, and the compositor graph. Existing animation, rigs, constraints, materials, textures and node networks stay in the native file. Existing assets need **Refresh Blender object metadata** to expose the new inventory; new imports include it automatically.

## Authoring dock

Select an object in the Outliner or 3D view. The new dock has Model, Sculpt, Rig & weights, Animate and Node graphs tabs.

- Model: translate vertices; extrude, inset or delete faces; subdivide or bevel edges; merge or smooth vertices; add subdivision, mirror, solidify, bevel and decimate modifiers.
- Sculpt: drag the paint brush directly on a selected mesh or place a brush numerically. Radius, displacement and falloff apply to the real Blender mesh. Strokes are saved as reversible edits.
- Rig: inspect bone hierarchy, create bones, pose existing bones, key poses, assign selected vertex weights, and animate existing shape keys. Imported armature modifiers, actions and constraints remain intact.
- Animate: save object transform keyframes, scrub/play the browser preview, render an authoritative Blender frame, or export an animated MP4 shot. Imported GLTF animation and skinning remain available in the stage preview; Blender renders remain authoritative for features that GLTF cannot represent.
- Node graphs: inspect graph structure and socket indices, add supported shader/geometry/compositor nodes, connect sockets by clicking output then input, edit numeric/vector/boolean socket defaults, and remove nodes. New geometry graphs receive input/output geometry sockets.

Every edit passes through authenticated workspace capabilities with scene authorization, optimistic locking and request receipts. Commands are replayed against the pinned Blender source in an isolated worker. Undo/redo reverses authoring commands across objects. Updating the Blender viewport generates an edited GLB, frame image and fresh topology/graph metadata; stale results do not replace newer revisions. Save and reopen the scene as a Blender asset to bake the current state into a new reusable source.

Interactive operations are bounded: 128 commands per object, 32 samples per brush stroke, 4096 selected elements per command and 500,000 vertices per edited mesh. The topology list samples the first 4096 elements. These are operational bounds, not Blender file format limits. Node creation uses an explicit catalog rather than arbitrary imported Python.

## Movie output

**Export movie shot** uses the existing quote/checkout and render queue. It produces an H.264 MP4 and editable Blender source. Export 1–2400 frames per shot; assemble longer productions using the existing media timeline. Video artifacts use the existing Lightek/community/OTT publication flow. This does not change pricing or start a payment or broadcast automatically.

## Live 3D stages

Live Studio includes a **3D stage + camera** program layout. Load a prepared Blender/GLB asset, choose an imported camera or automatic framing, and position the webcam subject in the set. The camera texture is a depth-tested plane inside the Three.js scene; objects can appear in front of or behind it. Chroma key removes the selected green/blue background. Adjust key tolerance, subject size and depth while watching the program preview.

The rendered 3D stage enters the same canvas captured by the live recorder and encoder. Existing graphics, audio beds, private recordings, Lightek broadcasts and configured social destinations continue through that program feed. Loading a stage does not start a stream. Camera cutout here uses chroma key, not AI person segmentation. Native Blender effects that cannot export to GLTF must be rendered to media before live playout.

## Deployment and verification

Apply `20261107190000_register_studio_authoring.rb` and restart Rails and the Studio queue workers. PWA cache is v52. Blender workers now mount the engine script directory so the shared authoring module is available in both imports and renders. The existing provisioning/update pipeline supplies Blender, NumPy and FFmpeg; Rails remains hosted on Passenger.

New real-Blender checks verify mesh/sculpt/rig/weight/shader/keyframe edits in an exported source, original-source immutability, resource ZIP import and a playable animated MP4. Additional native engine checks cover the remaining mesh tools, modifier families, shape keys, Geometry Nodes and compositor links. Browser checks cover authoring forms, direct sculpt painting, socket connections, mobile layout, GLB chroma/depth compositing, and 3D-stage capture through the live program mixer.

This is an expanded native authoring suite, not verified feature parity with every Blender or Maya tool. UV unwrapping, arbitrary node property editors, constraint construction, animation-curve editing, advanced sculpt brushes, simulation authoring, collaborative editing and Maya project import still need dedicated implementation and acceptance. Unexposed native data is preserved, but preservation is not the same as having an editor for it. Production deployment and third-party live delivery have not been exercised in this development environment.
