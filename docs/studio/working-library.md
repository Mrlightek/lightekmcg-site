# Working Studio library

Open **Studio → Library** in the PWA. The library brings production recipes, imported/generated media, and saved project scenes together.

## Built-in production recipes

All 22 entries in the original library now map to server-owned executable recipes through `studio.workspace.library.apply`. Pick a saved scene and use an item to create real scene objects, apply a material/motion to a selected element, or generate reusable media. The workspace shelf also has **Use in this scene** actions.

- Templates and collections add saved cameras, lights, editable geometry and, where appropriate, generated audio/graphics.
- Iris and Marcus are procedural mannequins for blocking. Environments, props, vehicles and architecture are editable primitive assemblies. These are useful production stand-ins, not finished artist-authored cast models.
- Camera/light packages save real camera positions, lens settings and light values. Material recipes change saved metallic/roughness/transmission/color settings used by Blender; the viewport reflects color, roughness, metalness and transparency.
- Memory Fragmentation creates animated geometric fragments. Neutral Walk Cycle applies a procedural blocking gait across a mannequin group, or a bob/advance loop on a selected object. It is not skeletal retargeting. Use **Play library motion** in the viewport to preview; saved Blender and GLB artifacts retain the motion.
- Neural Pulse Bed generates a four-second synthesized WAV and places it on the timeline. Lower Third System generates a transparent PNG with configurable title/subtitle and places it on the timeline. The simple bitmap lettering supports Latin A–Z, digits, spaces, hyphen and period.

Recipe applications and timeline insertions have idempotency receipts and optimistic locking. A retry cannot silently duplicate scene elements or replace newer scene state.

## Imported and generated media

Each supported item has a concrete workflow:

| Item | Uses |
| --- | --- |
| `.blend` / `.glb` | Interactive model preview; placement in an authorized saved scene; existing Blender render/export workflow |
| Image | Preview; append/layer on a timeline; social publication; live still or graphic overlay |
| Audio | Preview; append/mix on a timeline; social publication; looped live audio bed |
| Video | Preview; timeline editing/export; social/OTT publication; live program clip |

Choose a scene before adding or publishing media. **Publish / schedule** sends the source through the existing Studio artifact/publication worker and audience policy. It reuses the imported blob and a recorded source operation; it does not pretend an export or paid render ran. OTT publication requires an MP4; other formats must pass through the existing timeline export workflow first. Ordinary users can only use authorized assets and scenes. Platform super-admin access remains intact.

Every file can be downloaded. Failed imports have a **Retry processing** action. Search/category filters work over loaded entries, and **Load more media** retrieves older imports instead of hiding everything after the first 100. Saved projects/scenes and saved project templates remain accessible from the library.

## Live Studio

Open an image/audio/video item's **Use in Live Studio** link, or expand **Library sources** in Live Studio. Select the program image/video, optional image overlay and/or audio bed, then click **Load selected library media**. Video looping and audio bed volume are configurable. The source must decode in the browser; incompatible formats report an error and can be exported from Studio first.

Loading media is a local preview operation. A broadcast starts only through the existing explicit Start action and destination confirmation. Holding screen mutes both program audio and audio beds. Clearing/releasing sources pauses media and disconnects mixer nodes. The existing Lightek, Restream and simulcast transports are reused. This change retains the existing domain-based Live Studio site resolution.

## Deployment and verification

Run `bin/rails db:migrate` to register the four new library capabilities. No new media database tables are needed. The PWA shell cache is bumped to v47. Existing Blender/FFmpeg processing and queue configuration still apply.

Acceptance commands with the standalone bundle:

```sh
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/studio_library_checks.rb
LIGHTEK_TEST_BLENDER=1 BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb
CHROME_PATH=/path/to/chromium node test/javascript/studio_library_test.cjs
CHROME_PATH=/path/to/chromium node test/javascript/studio_live_library_test.cjs
CHROME_PATH=/path/to/chromium node test/javascript/studio_capture_transport_test.cjs
```

The tests exercise real database mutations and permission failures, signed publication flow, WAV/PNG decoding, mixed-media video export, native Blender render/GLB animation, library UI actions, actual browser media decoding, canvas program/overlay drawing, mixer gain changes and holding-screen muting. External Restream/TikTok delivery remains outside these local checks.
