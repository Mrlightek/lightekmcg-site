# Native Blender authoring and deployed runtime

Production verification after PR #173 found two concrete gaps: the demo imports failed because `STUDIO_ASSET_WORKER_IMAGE` was unset, and the library put the 129 JSON cards ahead of the actual Blender collection. Native templates also exposed cameras and a single proxy object rather than their editable source objects.

## Deployment

Normal Gatekeeper deployment now runs `lib/scripts/setup_studio_media.sh` as the application/Sidekiq OS account before restarting workers. It builds the default `lightek/studio-media:20261101` dependency image, then probes Blender with the same network/filesystem restrictions used by jobs. Rails remains on Passenger. An explicitly configured asset/render/media image is respected. Blender imports, renders and FFmpeg jobs use the default dependency image when their environment override is absent.

The worker account must already be able to access its Docker daemon. Setup checks this and stops with a specific error; it does not change group membership, expose the daemon or alter the Rails hosting model. The installer requires Blender 4.0 or newer. This repository's Ubuntu 24.04 image supplies Blender and FFmpeg.

After migration and worker restart, `studio:blender:bootstrap` queues Scattering Pebbles and Cozy Kitchen for the platform administrator on `LIGHTEK_STUDIO_SITE_HOST`. Existing ready entries are reused; failed entries retry. Source files finish installing asynchronously on the `studio` queue. Runtime dependency failures are visible in the Asset Browser. The install script itself was checked with a command-recording Docker fixture; a real image build/deployment still needs the production daemon.

For a legacy deployment outside the normal script, run the installer from the checkout as the worker OS account, migrate, restart workers and run the bootstrap rake task with the site hostname. No new image environment variable is required for the default setup. The native authoring capability migration is `20261101050000_register_blender_authoring.rb`, and the PWA shell cache is v50.

## Asset Browser

**Studio → Library** opens **Blender files** first. Official demo files show installation state, failures, native thumbnails and a direct **Open editable Blender project** action. **Install full Blender collection** queues the 12 approved imports. Presets/recipes, personal media and saved projects have separate views. JSON preset cards paginate in groups of 18, so they no longer bury the Blender files.

Files prepared before native object inventory was introduced must use **Refresh Blender object metadata**. New native projects require current inventory metadata. Their saved source snapshots remain independent of the library file. A multi-scene template uses a GLB proxy only when it belongs to that source scene; other scenes retain native object bounds and use Blender draft rendering for the actual image.

## Native scene editing

The importer records up to 2,000 native non-camera objects, plus cameras, with stable source identities, world transforms, collections, parents, materials, light values, modifiers and exposed numeric/boolean Geometry Nodes inputs. These become editable SceneObjects pointing into the pinned native source, rather than mesh replacements.

Native projects have a Blender Outliner and object Inspector. Save transforms, visibility, light power/size/color, Principled material overrides and available Geometry Nodes values. Duplicate creates an independent native object; removal records a reversible source override instead of modifying the library file. Native display names are applied after resolving source references. Shared camera/light/material data is copied when overridden. Unchanged native animation, modifiers, rigs, materials and node graphs remain in the source. Explicit property overrides clear only matching animation/driver channels. Changing a base color replaces its corresponding material input connection on the copy; changing roughness alone retains the texture connection.

The 3D preview maps real GLB mesh selections to native object identities. Source meshes can be selected and transformed individually. GLB's Y-up coordinates are converted to Blender's Z-up convention. **G / R / S** select move/rotate/scale tools. Native proxies are read-only containers; the Inspector directs users to native objects instead of saving ineffective proxy transforms. If a proxy is missing or cannot represent a native feature, bounds remain editable and Blender renders the authoritative image.

This provides native object/layout and exposed-parameter editing, not Blender's full mesh-edit, sculpting, shader-link or rig-authoring UI. Those richer structures are preserved in the editable `.blend`.

## Draft frames

**Render draft frame** opens the pinned source in Blender and renders the selected frame at up to 320 pixels and two Cycles samples. It is an authoring preview with no render checkout; it cannot request full-resolution output, GLB, project packages or an editable source export. Final exports retain the existing quote/checkout workflow.

Requests use project authorization, reuse pending work, bound request frequency, snapshot the source and render settings, and run on the Studio queue with a 60-second execution limit. The preview does not overwrite the production's final resolution or samples. Native edits use optimistic locking and transactional updates. Draft images are displayed directly in the workspace with their rendered frame number.

## Verification

`test/standalone/blender_authoring_checks.rb` includes the earlier native/JSON/library/broadcast/HTTP suites and real Blender proofs for source-object edits, native duplication/removal, lights, materials, Geometry Nodes inputs and bounded draft rendering. The original library source is compared byte for byte after editing/rendering. Browser checks cover the Asset Browser sections, native Inspector/Outliner, draft frame workflow and real GLB mesh picking with G/R/S tools. Installer/checkout/archive/transform checks run without production access.
