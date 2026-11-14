# Character body-motion clips

Open **Studio → Cast → Direct this take → Body motion clips**. Choose a character placed in the scene. Motion arrangements are saved independently of dialogue; a character can move without an audio take, or combine body motion with saved speech, expressions and gesture direction.

1. Click **Add motion clip**, then choose a source motion belonging to this character.
2. Trim its source frame range. Set its start in scene seconds, playback speed and repeats.
3. Set strength and optional blend-in/out times. Duplicate a clip to place a separate copy immediately after it, or remove individual clips.
4. Use layers 0–3 to combine motions. Higher layers evaluate later. Replace uses Blender's weighted replacement; Additive adds the source values and is best suited to actions authored as offsets. These are native NLA influence operations, not normalized motion matching or automatic transitions.
5. Click **Save motion arrangement**, then **Preview saved take** or quote/export the shot. The preview starts at the earliest saved dialogue/motion and covers up to three seconds. Full shot export uses the saved scene range.

The motion plan, source action references, timing and blend controls remain in the scene and render snapshot. Native exports retain editable NLA strips and their source Actions. Saving motions does not replace the dialogue take. A copied episode retains its own arrangement; revisions to that episode do not change the template or original episode. Reload saved motions fetches current scene data and discards this panel's unsaved motion edits.

## Available motions and sources

New Lightek toon builds contain three stashed native Actions: **Head nod**, **Look left and right**, and **Wave right**. They are starter head/arm motions, not a full-body walk or motion-capture library. The source tracks are muted until clips are placed. Older starter builds need a new build to include them.

For imported characters, the asset inspector discovers Actions already assigned to an armature's active Action or NLA clip/stash tracks. Each discovered entry records its source action, armature, optional Blender action-slot identifier, frame range and source scene frame rate. Registration in Cast pins that inventory to the prepared native source version. At most 64 source action entries are registered per character.

Unassigned Actions are not inferred or automatically retargeted. Assign or stash the action on the intended rig in Blender, save the packed file, import it and register that updated source in Cast. Characters registered before this inventory was added need reimport/registration to expose source motions. A clip cannot select an arbitrary action or another character's rig through browser parameters.

Selecting Studio clips mutes the selected rig's original NLA tracks and clears its active Action on the rendered instance. Original source tracks remain available as muted editable tracks. Removing all Studio clips restores the original source playback on the next render. The reusable character asset is retained. Separate instances share source Actions as read-only animation data; their strip timing, influence and gesture overlays are independent.

## Parameters and limits

| Studio control | Saved/render behavior |
| --- | --- |
| Source in/out | Frames within the registered action range; out must follow in |
| Start | Scene seconds, 0–600 |
| Speed | 0.25–4; source and destination frame rates are converted |
| Repeats | Integer 1–20 |
| Strength | 0–1, stored as native strip influence animation |
| Layer | Integer 0–3; evaluated in ascending order |
| Blend in/out | 0–3 seconds each, at most half the clip's duration |
| Blend mode | Replace or Additive |

Duration is `(source_out − source_in) ÷ source_fps ÷ speed × repeats`. Each clip must last 0.05–60 seconds and end within ten minutes. A character can have at most 32 clips. Two clips on the same rig/layer may overlap only within both adjoining blend ramps. Three overlapping clips on one rig/layer are rejected; use another layer. A strip has no influence outside its extent. Source action evaluation and constraints remain Blender's responsibility.

Saved dialogue gestures become an additive NLA overlay when a motion arrangement is present, preserving the body strips. Facial speech/expression animation remains on the character's shape keys. Legacy volume-only performances keep their previous behavior.

Saving checks the authenticated scene, character-bound action inventory, scene lock version and motion revision. Request keys are idempotent; changed payloads cannot reuse a key. A stale arrangement cannot overwrite a newer one. Motion saves increment the native scene revision so older previews are marked stale. Native scene sources are pinned by the existing render-source capture, including motion-only shots.

## Focused checks and remaining work

Checks cover source discovery through real native asset ingestion, save/retry/stale behavior, permission boundaries, trim/repeat/overlap validation, independent episode copies and the Cast UI. A native Blender proof verifies exact retiming and repeated duration, 50% influence, independent rigs, speech shapes, additive gesture overlay and packed audio in an editable `.blend`. Existing animated/audible character rendering is regression checked.

Automatic retargeting, motion capture/generation, IK/foot-contact correction, detailed human rigs, a live in-browser skeletal animation player, arbitrary external motion-library ingest and production-quality motion review remain separate work. Full production acceptance stays in the integrated verification sprint.

Engine contract: [Blender NLA strips](https://docs.blender.org/api/current/bpy.types.NlaStrip.html).
