# Performed character short

Open Studio Create → **Performed Short** in Dashboard or PWA. This guided entry connects existing Cast creation/placement, stock speech, Rhubarb speech analysis, saved performances, native cameras, preview rendering and paid shot exports. It does not require a Genesis connection.

1. Choose **Scene setup**: a plain character stage, the current editable scene set, or an existing library recipe such as Atlanta Night Exterior or Live Interview. The setup supplies editable sets, props and lights. Blocking mannequins are replaced by the selected performer. Select **Template cameras and cuts** to retain authored coverage, or **Frontal wide-to-close coverage** for the illustrated puppet. Choose a starter action or no added gesture.
2. Name the performer. Build an illustrated starter with skin/wardrobe/hair colors, or select an existing registered Cast asset from the library.
3. Enter a short spoken line such as **We protect this city.** Choose the stock US or UK English voice, or select a prepared recording lasting 0.2–2.8 seconds and no larger than 10 MiB. Import recordings through Media Library. The dialogue field can guide analysis of a recording.
4. Choose **Prepare performed short**. Worker phases report character build, dialogue preparation, speech analysis, camera direction and preview rendering. Reloading Studio restores the latest preparation for this creator and source scene. Preparation creates a separate scene in the same project; it does not overwrite the source scene.
5. Watch the private preview (three seconds by default; up to four with a step-in entrance). Frontal coverage cuts at 1.5 seconds; template coverage uses its saved cameras/cuts. Speech drives mouth shapes. The selected gesture is used where the rig supplies the binding.
6. Open the editable character scene to change Cast, face/gesture cues, body motion, cameras or scene settings. Saved project/show templates retain this scene, Cast bindings and takes; copying to an episode remaps camera cuts to its copied camera objects. The character remains a reusable Cast asset, and the generated/copied audio remains a separate owned recording.
7. Request the full shot export price. Repeated requests for the same current scene reuse its quote. Checkout, payment settlement, immutable source capture, full MP4/Blender output and failed paid-render recovery use the existing Studio/Dymond Bank paths.

## Two-character dialogue

Choose **Two-character dialogue** in Performed Short. Name two distinct characters and choose an existing Cast asset or build an illustrated performer for each. Each character has a separate US/UK stock voice; each speaking turn can instead use an owned 0.2–2.8-second recording (at most 10 MiB).

Add two to four ordered turns, with at least one turn per character and up to 80 text characters per turn. The worker measures actual recordings, adds a short opening and gaps, and rejects a complete conversation longer than eight seconds. Shorten the lines or remove a turn and prepare a new request if this limit is reached. Timings are derived from real audio, not estimated from text.

Preparation creates a separate editable scene, positions the two performers one metre either side of the template blocking center, and preserves the template floor height. Characters keep the same Cast asset across repeated turns. A two-shot opens the scene; slightly angled frontal close cameras alternate with the speakers so the flat illustrated artwork remains visible. Dialogue coverage replaces template camera cuts for this mode. Complex sets may need manual blocking/camera adjustment in the editable scene.

Every turn uses its own saved recording and phoneme analysis. Takes append to the existing performer, with a 0.25-second gap. Silent listener overlays add a small head reaction and raised brows when those controls are bound; they never add an extra voice or animate the listener's mouth. These are basic listening reactions, not full emotional acting or conversational gaze inference. Reaction timing is checked against the listener's own takes.

The same prepare/status/retry/quote capabilities accept `mode: dialogue`, `characters` (exactly two) and `turns` (two to four). Speaker indices are 0 and 1. The actor/site boundaries, immutable input recordings, source identity checks, saved preparation recovery and existing Dymond Bank export path still apply. Returning to the source scene restores the latest saved performance mode and inputs. Single-character requests retain their existing format and three-second behavior. No new provider credentials or Genesis connection is required.

## Production and saved-show templates

Expand **Start a production or saved show**, choose an available production template or your authorized saved show, and name the new project. **Create template production** calls the existing JSON preset builder or saved-template copy path. It retains the template's scenes, production metadata and saved brief, without rendering or publishing an episode.

The returned scene list has **Open** buttons. A scene opens directly in Performed Short, with **Current scene set** selected where supported. Choose its cast and dialogue, prepare and review a short, and then direct the remaining scenes. Whole-project/episode copies retain their own scene-object and camera-cut identities. Existing Timeline and production-master tools remain the subsequent assembly path; this launcher does not automatically perform every scene or assemble a full episode.

All registered asset-independent project-template types are listed. Scene setup choices come from the existing server-owned library catalog; they are not downloaded models. Saved shows are scoped to the selected site and existing project permissions. Changing a template or new-project name creates a fresh request; replaying identical launch inputs returns the existing project.

## Snapshot and staging behavior

Selected scene-object definitions and settings are frozen onto the preparation before queuing. A current registered cast can prefill the performer choice. Current Cast transforms are retained; compatible body-motion clips are retained only for the same registered source/profile. New performers use the template's blocking position and floor/deck height when available. Existing geometric collision checks remain enabled.

Template cameras and explicit/preset cuts are remapped to the copied camera IDs. Visible cuts are retimed to 12 fps and the three-second preview window. Frontal character coverage adds its own two cameras. Source preset definitions/briefs remain available for editing. Saved speech from a show is not silently reused for the new line.

Imported set-model sources receive independent asset records sharing frozen source blobs. Changing the original model afterward does not change that scene copy. A source changed before copying fails explicitly. This adapter allows at most 64 set/light/camera objects and a 256 KiB setup snapshot. Packed native-source scenes open in the advanced editor rather than being silently flattened into this scene-object adapter.

## Scope and artwork

The illustrated starter uses flat editable mesh drawings and emission materials, compatible with the existing performer face keys and three pose bones. It is a simple puppet, not detailed production character art, an automatic character designer, a complete human rig or a finished-show quality claim. Existing Cast assets can supply richer authored art and animation through their own bindings. Unbound arm gestures are omitted; speech still requires a registered mouth binding.

The scene is a technical character study toward original episodic animation. Full-body walking/combat choreography, detailed expressions, larger ensembles, arbitrary scene scripts, automatic conversion of layered-compositor backgrounds and production-quality visual review remain further work. No likeness or voice cloning is introduced.

## Execution and recovery

The prepare/status/retry/quote capabilities are `studio.workspace.character.scene.*`. They remain actor/site/project scoped, available through the existing authenticated PWA bridge, and registered by `20261119010000_register_character_scene_workflow`. Template catalog/launch capabilities are registered by `20261119020000_register_character_template_workflow`.

Inputs are bounded: a 1–60 character name, up to 80 dialogue characters, fixed stock voice choices, hex colors and owned source assets. Recorded input bytes are attached to the preparation before queuing; a copied source recording remains frozen. Reused Cast profile/source identity is checked before placement. Changed inputs cannot replay a request key.

Preparation uses the Studio queue. Durable receipts retain the new scene, reusable character, analysis, take and render. Retrying a failed preparation reuses those resources. Competing jobs defer to an in-progress worker; an eleven-minute watchdog marks an expired ten-minute attempt failed, including preparations waiting for another worker. A failure never becomes a successful substitute animation or analysis. Missing eSpeak-ng, Rhubarb or Blender must be fixed on the selected worker; the UI surfaces that failure and a retry action.

The deployed Studio media image already includes stock speech and the pinned Rhubarb 1.14.0 package. Synthesis is local eSpeak-ng; phonetic Rhubarb analysis is offline and should be reviewed against the voice recording. This is not professional voice acting or exact word alignment. Neural voices remain separate optional tools.

Preview rendering uses the existing CPU Economy configuration: one CPU render slot by default, 320-pixel preview edge, 12 fps, three seconds for a single study or up to eight seconds for bounded dialogue, and up to eight samples. Existing character build/import and analysis container limits still apply; this workflow does not establish free memory on a busy 2 GB host. Inspect and measure the intended installation.

## Acceptance

`test/standalone/studio_character_scene_checks.rb` covers actor boundaries, input limits, duplicate requests, retries and quote gating. With `LIGHTEK_TEST_CHARACTER_SCENE=1`, it builds a real illustrated character, synthesizes real speech, runs pinned Rhubarb, saves a phoneme take and camera cuts, renders a three-second MP4, checks audible PCM and reopens the Blender output to inspect changing mouth/bone values, camera switching, packed sound and editable controls. DOM checks cover the Dashboard and PWA flow without Genesis status calls.

The native CI preserves the MP4 and `.blend` proof. Production acceptance still requires a real PWA submission, worker execution, owner review, authorized full checkout and final Timeline/publishing verification. `studio_scene_templates_checks.rb` additionally verifies catalog coverage, production/saved-show creation, isolation, frozen sets, copied model sources and a real rooftop-template performance render. Local test output does not establish completed episode production.

`studio_dialogue_scene_checks.rb` adds request/source isolation and a real three-turn render with two Cast identities, separate audible voices, alternating cameras, phoneme cues, listener reactions and retry reuse. The saved Blender source is reopened to inspect its editable animation and packed recordings. `studio_dialogue_scene_test.cjs` covers both PWA and Dashboard submission, recovery, retry, preview and export quote. Audio mixdown supports both Ubuntu Blender 4.0 settings and newer operator arguments.

## Arrange performances into a sequence

In Performed Short, expand **Arrange performances into a sequence**. It lists your completed character performances in this project (up to 100). Choose two to twelve clips, move them earlier/later, and set in/out points in seconds. Reusing the same performance more than once is supported. Each trim must cover at least one twelfth of a second and stay within its current reviewed performance. A private review cut may last up to thirty seconds, with at most 50 MiB per source and 100 MiB total source bytes.

**Preview sequence cut** freezes selected preview blobs and ordered trims into a separate durable operation. FFmpeg uses the existing Timeline renderer to produce a 320×180, 24 fps private review MP4, preserving clip audio and adding silence where a clip has no audio. Picture order, trim duration, audio order and final runtime are verified in tests. No Cast is rebuilt and no Blender or Genesis call is required for this assembly step.

Sources must still match their rendered scene snapshots; a source scene changed after its performance preview needs a fresh reviewed performance. Fingerprints normalize JSON key order, including PostgreSQL JSONB ordering. Same-named character roles must use the same registered Cast source/profile across all selected performances. This is a continuity guard, not automatic wardrobe reconciliation or character recognition.

Review the cut and check **I reviewed this sequence**, then choose **Prepare sequence export**. If a selected performance has no current full scene export, the panel lists it and exposes its existing character export price/checkout. Finish those source exports, return to the cut and prepare its export again. Private preview bytes cannot be reused as public/delivery assets.

Once full sources exist, the service imports them through the existing artifact path and waits for actual media processing. It then creates a separate editable 1280×720, 24 fps Timeline scene with the ordered trims and requests its existing export quote. Repeated requests reuse that quote; a failed, paid sequence export can retry using its existing payment. Frozen full source blobs are attached to the export operation and consumed by the FFmpeg provider, so later Media Library changes cannot replace its rendered source bytes. A manually changed sequence timeline is exported through Timeline & Edit rather than being overwritten by this guided builder.

The panel restores its latest cut after reload and exposes retry after a failed preview. An eleven-minute watchdog detects expired ten-minute attempts. Worker scope/network permissions and frozen source identities are rechecked before rendering and before publishing a completed preview. This workflow does not publish automatically. Final video review and the existing publishing controls remain separate creator actions.

Capabilities: `studio.workspace.sequence.catalog`, `.prepare`, `.status`, `.retry`, `.quote`; migration `20261119030000_register_studio_sequence_workflow`. Nevaeh may capture `scene_id`, `name`, `shots` for preparation and `operation_id`, `reviewed` for export handoff. `studio_sequence_checks.rb` covers boundaries, JSON ordering, Cast continuity, watchdog/retry, real trimmed picture/audio, private-draft protection, actual full-source import, immutable source bytes, quote reuse, paid retry and editable Timeline behavior. `studio_sequence_test.cjs` covers PWA and Dashboard ordering/trimming, restoration, review gating, source checkout and processing-to-Timeline handoff.

## Guided acting cues

One-character studies and each character in dialogue now accept **facial cue**, **body action** and **entrance**. Facial cues are Neutral, Friendly smile, Curious brows and Surprised brows; they drive the existing smile/brow bindings during that character's own speech. They are bounded cues, not an emotion-recognition model or a complete expression rig.

New illustrated performers include source-native **Point left**, **Point right** and **Step in place** Actions, plus separate leg bones and parented leg/boot artwork. The legacy toon source motion vocabulary remains unchanged. Saved Cast sources are never rebuilt or silently upgraded. The panel disables motions not present in a selected Cast profile; direct requests also verify source Actions and facial bindings and fail explicitly if unavailable.

A step-in entrance moves the placed character 0.8 scene units toward its authored stage position while a short leg/arm cycle plays. Its root keys explicitly retain the scene's 12 fps. Both dialogue characters enter before speech (first line starts at 1.1 seconds); a one-character line begins at 1 second with an entrance and 0.1 seconds without one. Single previews retain at least three seconds and extend to four if needed so speech is not cut off. Dialogue, including its entrances and gaps, must still fit eight seconds. Original camera framing and source geometry may need artistic adjustment for a particular set; existing collision checks remain active.

Pointing plays a source-bound arm pose during the character's speech. Choosing a body action in the one-character form clears its default waving gesture; the server rejects competing wave/point direction on the same arm. Head gestures and silent listener reactions can coexist with arm poses. This is not automatic prop targeting, hand contact, inverse kinematics or full-body combat animation. Sitting and contact choreography remain future work.

Inputs are `emotion` (neutral/friendly/curious/surprised), `body_action` (still/point_left/point_right) and `entrance` (none/from_left/from_right). One-character requests carry them at the top level; dialogue carries them on each character. Inputs participate in request identity, saved receipts and reload restoration. Acting uses the existing MotionPlan validation, native NLA renderer and preview/export queues. Motion clips, root keys and the applied-direction marker commit together. An interrupted acting save rolls back its motion receipt so retry can prepare one complete arrangement. Repeated preparation retries preserve completed motion arrangements and do not duplicate clips or rebuild Cast.

`studio_acting_checks.rb` renders actual one- and two-character acting clips, checks timing/frame rate, reopens Blender to inspect root movement, leg/arm motion, smile values and packed speech, and checks source binding, input limits and retry reuse. `studio_acting_test.cjs` and the expanded single-character DOM test cover PWA/Dashboard controls, typed submission and saved-input recovery. The native CI retains both acting proof clips.


## Prop contact and control panels

Choose **Control-panel interaction** as the scene setup. In one-character or two-character mode, select **Activation button**, a hand and a face under **prop interaction**. Set reach start, reach time, hold and release. New illustrated performers include connected upper-arm/forearm bones and registered palm/wrist anchors. Reach bindings name the rig, connected upper/forearm bones and a forearm-parented hand mesh, with hand-local wrist and palm anchors; the palm faces local −Y. Existing Cast must already register compatible `reach_bindings`; older sources are preserved and cannot use contact until compatible bindings exist.

Contact accepts a static cube from the frozen scene setup and targets the center of its selected face. An analytic two-bone solver bakes editable arm and hand keys; it rejects targets outside natural reach instead of stretching the arm. The preview measures held-frame palm and wrist errors against a 2 mm tolerance. Other body/environment collision checks stay active. The control-panel button depresses during a front-face hold and returns on release. This is bounded contact posing, not a rigid-body simulation, arbitrary object grasping or automatic obstacle avoidance.

The optional `contact` input is `{target_id, face, hand, start, reach, hold, release}` at top level for a study or on each dialogue character. Faces are front/back/left/right/top/bottom; hands are left/right. IDs come from the chosen setup's `contact_targets` catalog. Start is 0–6 seconds, reach/release 0.4–1.5 seconds, hold 0.2–2 seconds, rounded to 12 fps; the complete contact must fit eight seconds. An entrance needs contact to start at or after one second. Choose no added body action or same-hand wave. Two characters cannot overlap contact intervals on the same prop. The renderer may still reject a reachable face if the arm or other geometry collides; reposition the prop or performer and review again.

Contact settings participate in preparation identity, persisted receipts and retries. The copied editable scene remaps prop references to its own objects. `studio_contact_checks.rb` reopens a real rendered source to measure palm/wrist continuity, button travel and packed speech; browser checks cover typed requests, old-Cast guards and restored contact controls in PWA and Dashboard.
