# Cast & Performance

This release connects a reusable native Blender character to a recorded performance, saved face/gesture cues, an animated preview and a movie export with audio. It is the character-performance step toward producing original Lightek shorts and episodes.

## Dashboard is the operating center

Open **Dashboard → Studio & broadcasting → Shows & episodes**. Productions and saved show templates appear alongside their scenes. Each scene has **Cast & performance**, **Set & cameras** and **Edit & mix** entry points. The workspace opens inside Dashboard on the application’s own domain, using the existing Studio engine and authenticated API. **Cast library** lists reusable performers; release queues, channel scheduling and OTT settings stay in the same control room.

If a central operator selects another application/domain, Dashboard links to that application’s workspace instead of embedding it across domains. Scene authorization is checked against the selected application before embedding. This release does not introduce a separate season/episode management database or rename generic projects into a complete series-management system; that company-level organization remains a following stage.

## Make your first performed shot

1. In **Dashboard → Studio & broadcasting → Shows & episodes**, open a scene’s **Cast & performance** workspace. You can also select that tab from an open Studio scene.
2. Under **Create a Lightek toon performer**, choose a name, skin color, jacket color and hair color. Build the performer. The Studio queue creates an original native `.blend`, prepares the viewport proxy and registers its face controls. The Cast panel polls until it is ready; failed builds expose a retry button.
3. Choose **Place in this scene**. Empty scenes receive a portrait camera and lights. Existing set/camera/lighting choices remain yours. Arrange the character in the 3D workspace.
4. Use **Import character / dialogue / singing** to open Library. Import a recording, then return to Cast & Performance and refresh Cast. Choose the recording, source in/out points, scene start and voice gain.
5. Add timed face cues: smile, blink, brow raise, mouth-wide or mouth-round where the character supports them. Jaw-open cues can override volume automation for a particular interval. Add nod, head-shake or arm-wave cues when corresponding bones are bound. Cue times are relative to the selected take, not the source recording or episode.
6. **Save performance**. The mouth track follows the recording's volume and goes quiet during silence. This is volume-following articulation, not automatic phoneme recognition. For singing, an isolated vocal track gives more useful mouth movement than a full instrumental mix.
7. **Preview saved take** queues up to three seconds of camera animation, starting at the earliest performance. The preview uses at most 320 pixels per dimension and eight samples. Review the private playable MP4. A changed scene marks an older result stale; save and request another preview.
8. **Export saved shot · quote** enters the existing render quote and payment flow. Finished output includes the animated MP4 with the recording and an editable `.blend` with facial/bone keyframes and packed sound strips. Previewing does not initiate payment or publish media.
9. In Delivery, use **Use in edit library** on completed media to assemble the rendered shot with other footage, graphics, music and sound effects.

The first-party performer is a deliberately stylized toon rig. It establishes an executable, editable path without external AI credentials. It does not reproduce the photorealism, wardrobe complexity or performance quality of the Instagram reference.

## Bring a detailed character

Import and prepare a **standalone packed `.blend`** through Library. Open **Register your Blender character** in Cast & Performance:

- Choose the source file and its source scene.
- Give the reusable Cast member a name.
- Bind **jaw open** to an actual facial mesh/shape key. This binding is required.
- Bind other available facial shape keys to smile, blink, brow raise, mouth-wide and mouth-round. Each control needs a distinct shape key.
- Optionally bind head, left-arm and right-arm controls to actual armature bones. Each role needs a distinct bone.

Save the character, then place it in any authorized scene. Registration creates an independent asset record referencing the prepared source blob. Source objects, materials, armature modifiers, parents and native animation remain in Blender. Performance direction keys the selected face/rotation channels; it is not a universal rig-retargeting system. Bone axes vary by rig, so gesture suitability needs checking with that character.

Packed resource ZIPs are not accepted as Cast sources in this first implementation; open and pack the character into a standalone `.blend`, then import it. Character scene inventories must contain 1–256 supported objects. Cameras and lights from the source are excluded when placing a performer into a production set.

## Several characters played from the same source

One registered character can be placed multiple times in the same scene. Each placement has an independent transform, face animation and performance recording; the native source stays unchanged. Import mapping uses original source object names, so Blender's automatic `.001` naming on a second instance does not break the bindings. Render operations pin source and recording blobs so replacing a library attachment cannot silently change a queued shot.

This supports independently directed instances of the same source. Making several characters with your own likeness and distinct faces/voices still requires the likeness/performance-transfer workflow planned below. The current release does not automatically turn a selfie or video into a rigged likeness or clone a voice.

## Reuse a show as separate episodes

Save a production with its recurring cast, sets and cameras using **Save as template**. In **Studio → Templates**, enter an **Episode / project name** and create a new project from the saved template. Cast bindings and saved takes are copied with the scenes; editing or removing a take in the new episode does not alter the source template. Internal request receipts are cleared on the copy.

For a 3–10 minute episode, direct and render short shots, bring them into the editing library, arrange the finished sequence, and export a delivery master. The existing timeline supports up to ten minutes per assembly. There is no automatic whole-episode generation or conform in this release. Native Lightek publication remains connected; direct social publishing continues to depend on the destination adapter and account setup.

## Limits and deployment

- Up to 16 Cast placements per scene; 1–256 supported source objects per character.
- Up to 30 seconds per recorded take. Source in/out can address the first two hours of a recording; the performed interval must fit within the first ten minutes of the scene.
- Up to 64 face cues and 32 gesture cues per take. Overlapping cues on the same control/bone are rejected.
- Four pending performer builds per creator. Preview jobs are reused while pending/running and bounded to four new previews per minute across accessible projects.
- Full movie exports retain the existing 2,400-frame shot limit. Native recordings, clips and templates remain actor/site scoped.
- Voice synthesis, phoneme alignment, motion capture, generative character modeling and voice cloning are not implemented here.

Apply `20261111190000_register_studio_character_performance`, restart Rails and Studio workers, and serve PWA cache v57. New Python scripts run through the existing isolated Blender/FFmpeg dependency image; no new external service or API credential is required. The scripts are supplied with the application checkout and mounted/copied into the worker job. Rails remains on the host.

## Next production milestones

1. Creator camera/video capture and imported performance takes; synchronize multiple recorded performances against a shared scene clock.
2. Image/video surfaces, keyed cutouts, masks, depth and per-layer effects composited with the character scene.
3. Face/performance transfer and higher-quality lip sync, with separately reviewed code licenses, model-weight terms and compute requirements. No deepfake/face-replacement package has been installed or selected in this release.
4. Episode/shot assembly and recurring-character continuity for template-based 3–10 minute shows, including multiple roles derived from one creator. Publish masters to Lightek and connected destinations; retain downloadable masters for other platforms.

## Acceptance

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile LIGHTEK_TEST_BLENDER=1 bundle exec ruby test/standalone/studio_performance_checks.rb --name /test_performance_/
node test/javascript/studio_performance_test.cjs
```

The native acceptance creates a real performer, places two instances, directs one, renders a movie and reopens its `.blend`. It checks audible samples, visible animated frames, independent face data, gesture animation, correctly trimmed packed audio and immutable queued source recordings. The DOM acceptance exercises build/register/place, cue preservation, save and private preview controls. Full browser media/visual QA and production deployment still need verification.
