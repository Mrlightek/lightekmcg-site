# Original JSON media packs → Blender presets

The recovered text-to-video generator archives contain 129 distinct definitions across their historical versions. `config/studio/packs/original_media.json` retains the original JSON, archive/path and SHA-256 of each source file. Later versions take precedence for duplicate keys. Inheritance is resolved before compilation, with missing parents and cycles rejected. These are the original packs, not replacements inferred from their display names.

Open **Studio → Library → JSON media presets & project templates**. Search and category filters include these presets. The saved Templates page links to the same collection.

Each card offers:

- **Create a new production**: independent project/production and scenes derived from the show’s shot plan, episodes or segments. Per-segment camera references and durations are applied.
- **Add scenes to an existing project**: append the template’s scenes to the selected scene’s project without replacing its existing work.
- **Apply inside a saved scene**: append cameras, blocking geometry or native preset instructions, merge explicit render settings and optionally apply a material to an editable selected primitive.

The open project workspace also has a **Blender JSON presets** picker. Apply to the current scene or selected element there. Presets requiring a file dependency use the library card’s authorized asset selector. Existing save-as-project-template and create-from-saved-template workflows retain these settings; copied projects reset preset request receipts.

## What compiles

| Original fields | Blender result |
| --- | --- |
| Camera profiles/grammar, lens/lens_mm/focal_length, sensor width, DOF/f-stop, location/radian rotation | Native cameras with normalized data; known movement instructions create editable camera keyframes |
| Production render defaults / video formats | Resolution, FPS and FPS base, including 59.94 formats |
| Show plans, segment durations, beat cadence | Independent template scenes, frame ranges and named timeline markers |
| Industry/geometry sets | Editable procedural staging objects; these are blocking sets |
| Geometry Nodes groups/parameters | Native node group/modifier with exposed parameter inputs; basic procedural geometry rather than finished source models |
| Material catalogs | Reusable native material datablocks; optional selected-primitive assignment |
| Titles, lower thirds, scorebugs and brands | Editable camera-parented Blender text objects |
| Compositor lists | Supported glare, color balance, blur and lens-dispersion nodes connected after the existing image chain |
| Explicit brand/geometry pack references | Composed child preset directives |

Every applied preset also becomes a named JSON text datablock in the exported `.blend`. The complete resolved source remains there even when a field is a creative direction rather than an executable Blender parameter. Cards show the concrete generated outputs separately from retained instructions.

Some old definitions name files that were never included in their JSON archives. Rig/native-library presets require a prepared, packed `.blend` from the authorized asset library; audio-file presets require a real audio asset and use the existing timeline workflow. They do not read the old relative filesystem paths or invent missing files. Bundle-backed native projects can still be created through the native Blender template workflow.

Voice direction, training policies, ingest rules, action names without supplied native actions, abstract style/edit language and report schemas remain project instructions and Blender text. This adapter does not synthesize voices, train models, manufacture missing rig actions, bake fluid simulations or implement every named edit/compositor effect. The exact original definitions remain available to extend the compiler. Generated camera movement is editable blocking motion, not subject-tracking or a finished authored performance.

## Authorization and rendering

`studio.workspace.blender.preset.use` uses existing site/project/asset policies, request receipts and optimistic scene locking. Creation/application is transactional: failed dependencies or stale saves roll back appended objects/scenes. Repeating a request does not duplicate the template. Source JSON is server-owned data, never evaluated code. Native projects retain their pinned Blender sources; presets are composed after opening those sources.

Rendering uses the existing paid quote/checkout path. Preview remains a still at the selected frame; camera animation and markers are retained in the editable `.blend`.

## Deployment and checks

Run `bin/rails db:migrate`, including `20261101040000_register_blender_media_presets.rb`; restart workers and serve PWA cache v50. No media-table migration is needed.

```sh
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_preset_checks.rb
CHROME_PATH=/path/to/chromium node test/javascript/studio_library_test.cjs
```

The suite compiles all recovered definitions; verifies production/scene creation, inheritance, idempotency, stale saves, tenant boundaries and missing-file rollback; and reopens real Blender exports to inspect cameras/DOF/animation, 59.94 FPS, title objects, materials, compositor nodes, Geometry Nodes and timeline markers. A separate native-template composition check confirms the original world, rig and node graph survive without modifying the library source. Optional official demo download checks use the environment variables documented in `native-blender-engine.md`.
