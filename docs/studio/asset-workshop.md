# Studio asset workshop

Studio & broadcasting OS now links directly to **Create in Studio** and the **Blender files & asset library**. The workshop route is `/lightek/index.html#/studio/workshop`; the existing new-production wizard remains at `#/studio/create`.

## Create and reuse

Choose a cube, sphere, cylinder, plane, interview stage, modular room, rooftop, glasshouse, lighting rig or animated fragments. Set size and surface color/roughness/metallic, then create a production or add the elements to an existing scene. New productions include cameras and lighting. Every part is a saved editable scene object, visible immediately in the existing 3D workspace. Fragment animation positions scale with the geometry.

Use **Save scene as Blender asset** from the workspace toolbar to snapshot the current saved scene. A Studio queue job exports its `.blend` source, retains its resource bundle and credits where present, prepares native inventory and an optional GLB/thumbnail, and saves it in the asset browser. This saves editable source without a render checkout; final media exports retain their existing workflow. Failed exports appear in the library and can be retried. Repeated submission uses the same receipt rather than producing duplicate assets.

Open the saved Blender file as a native production to edit its objects, materials, cameras, lights and exposed Geometry Nodes inputs. Original projects and library sources remain independent. Existing import accepts `.blend` and `.glb` files.

These are bounded procedural tools; they do not perform AI text-to-3D inference. Mesh sculpting, topology editing, rig creation and shader-node wiring still require desktop Blender. Live composition and third-party social publishing retain their existing capabilities; this change does not claim that an arbitrary Blender scene is automatically a live broadcast input.

## Installation and health

Apply `20261107153000_register_studio_native_creation.rb` and restart the application and Studio workers. The PWA shell cache is v51. The existing deployment/provisioning script `lib/scripts/setup_studio_media.sh` installs Blender and FFmpeg in the isolated media dependency image while Rails remains on Passenger.

The dependency image explicitly installs NumPy, required by Blender’s GLTF exporter even when optional package recommendations are disabled.

Production runtime health now actually starts Blender in a networkless, read-only, unprivileged container and checks the version marker. An image existing locally no longer produces a false ready result. This source change does not itself verify or install the production server's runtime.

## Verification

Run the standalone creation checks with the standalone Gemfile, setting `LIGHTEK_TEST_BLENDER=1` and `BLENDER_BIN` to a Blender 4+ executable for the real export/import round trip. Run `test/javascript/studio_creation_test.cjs` with `jsdom` available to test workshop forms, scene/version payloads, save receipts, failures and preservation of the existing production wizard.
