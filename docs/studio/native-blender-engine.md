# Blender is the Studio engine

Lightek Studio wraps native Blender projects. The `.blend` attachment is the editable source used for native template rendering; a generated GLB is an optional browser preview. Preparing a file records its scenes, cameras, frame/render settings, node/rig counts, dependency warnings and embedded credit text. Preview failure does not discard a usable native source. Files from a newer Blender major/minor release than the worker are rejected with an actionable version message.

## Library workflow

Open **Studio → Library → Blender demos**. The initial catalog contains 12 selected official demo downloads, including Classroom, Cozy Kitchen, Gaku, Cube Diorama, Geometry Nodes examples, fur and simulation examples. Import queues an authorized download and native preparation; catalog cards are not preinstalled assets. The registry is `config/studio/blender_demos.json`. Each entry pins its official URL, author, license, minimum version and source page. The collection is at <https://www.blender.org/download/demo-files/>. Preserve the embedded license/README and review its terms when distributing modified work.

For a ready native asset, choose one source scene or all scenes and **Use Blender template**. This creates an independent production/project with pinned source attachments. Later library reprocessing cannot change that production or a queued render. The original library file stays unchanged when cameras or scene settings are edited. Older imports expose **Prepare native Blender**. Uploaded standalone files with unresolved external dependencies must be packed in Blender before use; official ZIP imports retain their resources automatically.

The browser shows a proxy and editable camera controls. Native node graphs, rigs, worlds, compositor data, packed textures, animations and original scene objects remain in the underlying Blender project. This is not a browser node editor or a complete Blender UI. Download the source to edit those elements in Blender, then reimport it.

## Native cameras and rendering

Seven camera presets create real Blender cameras. The editor exposes perspective, orthographic and panoramic projection; millimeter/focal-angle lens settings; sensor fit/dimensions; lens shift; clipping; orthographic scale; depth of field, focus target/distance and aperture; six panoramic modes with fisheye/crop/polynomial controls; and stereo convergence/interocular settings. Controls save through authorized workspace capabilities with optimistic scene locking.

Select the active camera and set frame range/current frame, FPS and preview samples. **Render active Blender camera** enters the existing render quote/checkout workflow. Panoramic rendering uses Cycles. Native projects open their pinned `.blend` and source scene instead of reconstructing the scene from a preview mesh. Untouched animated camera properties retain their animation; explicitly edited properties override their corresponding animation channels on independent camera data. Native rigs and constraints remain in place.

Render artifacts include an editable `.blend`, preview and manifest. Native templates do not require a GLB export to render. ZIP-backed templates also produce an editable `project.zip` containing `scene.blend`, the dependency tree and source credits. Credits propagate to publication metadata and appear on community posts. A Blender project render currently produces a still preview at the selected frame; video animation remains a separate export workflow.

## Workers and deployment

Run `bin/rails db:migrate`, including `20261101030000_register_native_blender_studio.rb`, to register the five native actions. No new media tables are required; Active Storage stores native sources and bundles. Restart the `studio` queue worker and serve PWA shell cache v50.

Production imports and renders execute Blender in isolated containers. Normal deployment installs the default Studio media image automatically; see [Native authoring deployment](blender-authoring.md). Set `STUDIO_ASSET_WORKER_IMAGE` to override it; optionally set `STUDIO_RENDER_WORKER_IMAGE` to use a different render image (it defaults to the asset worker image). Images need Blender and a writable `/tmp`; the application launches renders without network access, with a read-only filesystem, no added capabilities, a writable job directory and bounded memory/CPU. Local development uses `BLENDER_BIN` or `STUDIO_RENDER_ENGINE_BIN`. Use a worker version at least as new as each chosen source file. The tested runtime is Blender 4.0.2. Application hosting remains unchanged.

Downloads accept only pinned HTTPS URLs on approved Blender hosts, with bounded redirects and a 512 MB limit. ZIP extraction rejects traversal/symlinks and limits expanded size to 2 GB and template count to 100. Blender auto-execution is disabled. Missing dependencies and optional preview failures remain visible in library metadata.

## Verification

The native suite includes the existing library/broadcast/HTTP checks plus real Blender fixtures with multiple scenes, Geometry Nodes, packed texture, armature, camera rig, shared animated camera data, panoramic/orthographic cameras and external video resources. It verifies immutable sources, edited camera exports, bundled resource resolution, credits, tenant boundaries, stale saves and demo import queuing.

```sh
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/native_blender_checks.rb
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb
CHROME_PATH=/path/to/chromium node test/javascript/studio_native_camera_test.cjs
python3 -m unittest test/operations/blender_demo_archive_test.py test/operations/studio_transform_test.py
```

`LIGHTEK_TEST_BLENDER_DOWNLOAD=1` additionally exercises the real official demo download job. `LIGHTEK_BLENDER_DEMO_DIR` points to downloaded `pebbles.blend` and `cozy-kitchen.blend` fixtures. These network checks are optional in CI; deterministic native fixtures run there. Local full verification passed 71 tests/842 assertions with both optional checks enabled. The full production application bundle and external delivery were not exercised by this standalone test runtime.
