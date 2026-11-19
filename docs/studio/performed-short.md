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


For a shared prop action, select **Pass a parcel across the counter** in **Dialogue scene setup**. Character 1 sends the parcel to Character 2. Choose new illustrated performers or saved Cast with the required right and left reach bindings. Facial cues, dialogue and reusable Cast work as usual. The preset controls the arm movement and keeps a two-shot on both hands during the exchange. The receiver makes contact before the giver releases, and the parcel stays supported by the counter.

Through the same prepare capability, use `scene_template: counter_handoff` and `mode: dialogue`. The setup supplies its own prop contacts, so omit per-character `contact` and keep the performers in place.

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

In Performed Short, expand **Arrange performances into a sequence**. It lists your completed character performances in this project (up to 100). Choose two to twelve clips, move them earlier/later, and set in/out points in seconds. Reusing the same performance more than once is supported. Each trim must cover at least one twelfth of a second and stay within its current reviewed performance. A private review cut may last up to 60 seconds, with at most 50 MiB per source and 100 MiB total source bytes.

Choose **Revise take for clip** to reopen a performance created from this source scene with its saved Cast. Prepare and preview the revision, then choose **Use revised take in clip** to place it back into that same clip. Studio keeps your trim points where they fit and flags any adjustments for a shorter take. A changed cut needs a new sequence preview and review before export.

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

The optional `contact` input is `{target_id, face, hand, start, reach, hold, release}` at top level for a study or on each dialogue character. Faces are front/back/left/right/top/bottom; hands are left/right. IDs come from the chosen setup's `contact_targets` catalog. Start is 0–6 seconds, reach/release 0.4–1.5 seconds, hold 0.2–2 seconds, rounded to 12 fps; the complete contact must fit eight seconds. An entrance needs contact to start at or after one second. Choose no added body action or same-hand wave. Manual contacts on the same prop must use separate intervals. The renderer may still reject a reachable face if the arm or other geometry collides; reposition the prop or performer and review again.

Contact settings participate in preparation identity, persisted receipts and retries. The copied editable scene remaps prop references to its own objects. `studio_contact_checks.rb` reopens a real rendered source to measure palm/wrist continuity, button travel and packed speech; browser checks cover typed requests, old-Cast guards and restored contact controls in PWA and Dashboard.


## Versioned character mechanics: bench v1

The original bench action remains available as version 1 for saved performances. New bench selections now use version 2, described below. In **Performed Short → One-character study**, choose **Walk, sit and stand**. The setup selects its bench action and seat automatically. Build a new illustrated performer or reuse Cast with `mechanics.profile = illustrated_biped` and `mechanics.version = 1`. Review the eight-second full-body preview; the editable scene and existing export/checkout remain available.

The coordinated action walks to the bench (0–2 s), turns toward the camera (2–2.5 s), sits (2.5–3.25 s), holds the seat for dialogue, stands (6.4–7.25 s) and settles. Speech begins at 3.4 s, so a 0.2–2.8 s recording ends before standing. This action owns root movement, leg solving, arm-to-lap posing and support contacts; separate entrances, added body actions, arm gestures and prop contacts cannot be combined with it. Facial cues remain available. Bench v1 is a single-character action, not a new two-character choreography engine.

The architecture separates source rig/physical bindings (Model), the immutable timed action plan and versioned driver registry (ViewModel), and illustrated character meshes (View). `Studio::Performance::Mechanics` validates the source contract and compiles a saved plan. `blender/mechanics.py` resolves the pinned driver; `bench_v1.py` coordinates locomotion, turning, sitting, lap arms and standing with the shared `kinematics_v1.py` two-bone solver. Arm-to-prop contact also uses that solver. New drivers/versions can be added without replacing earlier calibrated implementations.

The plan records the action/profile version, native source blob, target seat and SHA-256 fingerprint of its versioned driver/solver. Changed code or incompatible bindings fail explicitly rather than silently changing the performance. Saved-template copies remap the seat reference and preserve the version/fingerprint. Finished Blender sources retain baked keys independently of future solver changes. Keep old driver files intact when adding versions.

Calibration v1 supports the generated illustrated proportions, unit scale, two connected leg chains, both arms, sole anchors, pelvis support and the included 0.44 m seat. The seat must retain its calibrated dimensions and transform. Different body proportions, seat heights, arbitrary paths, obstacle avoidance, dynamic balance, mass/force simulation, cloth and multi-character physical interaction need additional calibrated models. This first version is deterministic kinematic contact posing; it does not claim a general real-world physics simulator.

The renderer verifies all 96 frames, ankle/wrist continuity, grounded stance anchors, and pelvis support over the seat within 2 mm. Only the registered pelvis/seat surface contact is authorized; the rest of the character and environment remain subject to collision validation. Obstacles reject the preview. Planted feet remain fixed while the body sits and stands. Shortened jacket artwork and segmented thighs/calves let the new source fold without the old jacket/hands clipping the seat. Existing Cast assets are not rebuilt.

`studio_mechanics_checks.rb` renders the continuous action, reopens its native source to independently measure support and foot placement, checks frozen driver identity/retry reuse, and rejects a changed driver fingerprint and blocked walkway. `studio_mechanics_test.cjs` covers PWA/Dashboard selection, typed input, old-Cast guards, restoration, retry, preview and the existing export quote. Native CI retains the video and editable source.


## Direction, character views and surface frames

New bench selections use `{action: "bench", version: 2, target_id: "seat"}`. The performer walks sideways in profile, facing along the path, then turns and steps into the sitting orientation before sitting. Source-bound front/side drawings share the same rig. Front/side mouth, blink and brow shapes retain the performed speech/facial cues. Different drawings do not change the physical model: canonical physical meshes remain evaluated even when their render drawing is hidden, while added side artwork is excluded from physical collision geometry. Bench v1 files and fingerprints stay intact for earlier scenes.

`biped_v2.py` provides reusable foot tracks, per-foot planted orientation and limb posing. Each turn moves one foot at a time; it does not spin planted feet with the torso. `spatial_frame_v1.py` supplies right-handed local frames from a surface origin, outward normal and tangent. The floor, ceiling and four wall orientations are tested for correct normals, determinant and world/local round trips. Current action profiles still walk on a calibrated horizontal floor; a coordinate frame is not a wall-walking or gravity simulation.

New source builds register `views.version = 1` and explicit front/side source-object lists. Reuse requires compatible view bindings as well as physical bindings. Direction-aware action files have their own fingerprints and reuse the unchanged earlier solver/driver utilities where listed. Adding or changing a version must preserve the dependencies pinned by existing approved scenes.

## Pick up, carry and put down

Choose **Pick up, carry and put down** for the parcel and two calibrated tables. This selects `{action: "carry", version: 1, target_id: "parcel"}`. It uses the illustrated biped v1 physical contract plus front/side drawing bindings. The character reaches, attaches the parcel to the left palm at its upper front edge, lifts it clear, turns to face the walking direction, carries it, turns back, places it and releases. Speech starts at 2.3 s during the carry. The complete action remains eight seconds at 12 fps.

The grip is an editable native Child Of constraint with explicit constant-interpolated attachment/release events (frames 10 and 67). The parcel follows hand orientation and position while held; on release it retains its placed world transform independently from later hand movement. The renderer measures palm contact, wrist/ankle continuity, grounded stance, support on both tables and post-release drift within 2 mm. Carried parcel geometry is checked against the environment on every frame; authorized support contact cannot penetrate the table and must fit its footprint. Body/arm collision checks remain active.

This is a rigid palm/rim attachment for one calibrated parcel, not finger articulation, arbitrary-size grasping, force-based handling or a general free-fall simulator. The root path leaves clearance from the tables, and the arm path goes around the body rather than carrying the parcel through the jacket. Scene copies remap the parcel and both support references. Inputs, source bytes, driver dependencies and retries remain frozen/scoped as in the bench path.

## Attention and focal points

**Attention target** supports the active camera, a prop from the scene setup, or the conversation partner in two-character mode. Choose when attention starts/stops; times snap to 12 fps within the eight-second budget. The optional input is `attention: {kind: "camera" | "object" | "partner", start, end, target_id?}` at study top level or on each dialogue character. Only object mode accepts `target_id`; it must come from this frozen setup. Partner resolves to the other prepared character. Camera resolves to the actual active render camera at each frame, including cuts.

A registered `attention_binding` names the head rig/bone and its armature-rest eye anchor. New builds register that calibration; saved/custom Cast must provide its own eye anchor instead of inheriting a guessed height. Attention bakes the registered head independently of body movement and restores the action's head/drawing state outside its interval. Head artwork can face differently from torso artwork. Head aiming is bounded to 75° yaw and 25° pitch relative to the body; the native report identifies clamped frames that need a body turn. Independent eyeball aim/saccades, automatic body reorientation and actions inferred from arbitrary gaze are further work. Mechanics targets and focal points reference the same scoped scene objects, but changing gaze does not silently redirect locomotion.

For a fourth-wall address, choose the active camera while the character speaks. The bench action defaults attention timing controls to its seated interval. Camera selection/cuts are established before gaze baking so the saved scene aims at the same camera used to render it. Attention drivers are fingerprinted; target references are remapped when copying a saved show. The controls extend the existing prepared-scene/quote path and do not add a new engine or payment provider.

Acceptance includes native side-facing/turning inspection, a real grip/carry/release scene, blocked-parcel rejection, camera aim measured independently after reopening Blender, bounded partner attention without root rotation, restoration after gaze ends, and the six surface frames. Browser checks cover one-/two-character typed focal points, saved-input recovery, old-Cast guards, retry and existing quote handoff in both Dashboard and PWA. CI retains directional, attention, carry and editable-source proofs.

## CPU contact physics: physical finger grasp v1

In **Performed Short → One-character study**, choose **Physical finger grasp** and keep **Template cameras and cuts** for the wide view and hand close-up. The setup selects `mechanics: {action: "grasp", version: 1, target_id: "ball"}`. Build an illustrated performer or select compatible Cast. This is a separate eight-second study: approach, close, lift, hold, lower, open and withdraw. The original rigid parcel-carry routine remains version 1; selecting it does not run this new hand solver.

The mechanics plan freezes `blender/physics/human_v1.json`, its SI units and the implementation fingerprint. The authored adult calibration includes 75 kg body mass, arm/hand segment mass fractions, 5–145° elbow flexion, per-link finger flexion limits, 0.35 N·m finger motor limits, friction, 9.80665 m/s² gravity and a 0.2 kg sphere of 0.045 m radius. These are a stylized production calibration, not a medically validated model of every human. New proportions/materials need reviewed profiles and calibration. Never change this version's files to alter an approved performance; introduce a new profile/driver version.

MuJoCo 3.3.7 runs 4,000 fixed CPU steps at 0.002 seconds, without its renderer. Fifteen moving capsule links form four fingers and an opposed thumb. Limited position motors curl them against a free-jointed load; contact forces, friction, inertia and gravity determine whether the load moves. The object has no parent, `Child Of`, weld, adhesion or hand attachment. The simulation is baked into editable Blender object transforms for the finger segments and load, with the model XML and sampled physics report embedded in the native source. Blender still renders the picture. No ComfyUI, CUDA or GPU is needed for this study.

The palm translation follows a bounded motor-driven approach/lift/return path. The standing character and arm reach use planted feet and anatomically bounded IK with a downward elbow bend. Hand link inertia consumes the profile's hand mass budget; the other arm segment masses contribute a recorded shoulder gravity-load estimate. **The torso, shoulder, legs and locomotion are not yet dynamically simulated**, and the estimate is not a solved shoulder motor. Whole-body balance, arbitrary hand shapes, grip styles, walking with this physical grip and multi-character physical interactions remain future drivers.

Acceptance checks solver version, torque, penetration below 2 mm, a successful lift above 13 cm, supported return, wrist/ground error, elbow limits and scene collisions. Sphere rolling after release is allowed; no artificial freeze is added. The physical hand's contact with its sphere/table has a narrowly scoped penetration check; the rest of the character and environment retain collision validation. Extra obstacles still fail explicitly. Retry preserves frozen source/profile/targets, and copied scenes remap both the load and table references. Existing private-preview and paid-export workflows are reused.

`studio_physics_test.py` verifies contact lift/release, inability of a weak grip to lift the same load, mass-sensitive response and deterministic fixed-step results. `studio_grasp_checks.rb` renders through the real prepared-scene path and reopens the native source to inspect fingers, limits, free-load motion and embedded physics evidence. PWA/Dashboard DOM checks cover selection, typed inputs, restore, retry, preview and quote handoff; these checks do not establish a live production session.

The media and workstation Docker builds install the pinned CPU dependencies in `/opt/lightek-physics/venv`; the media deployment probe verifies the solver in the actual render image offline. The existing source-digest deployment helper rebuilds the default media image when this build context changes. Custom images must include the same runtime. Local development can select its own installed interpreter with the **server-side** `STUDIO_PHYSICS_PYTHON` environment variable; requests cannot supply executable paths. A missing runtime fails the grasp job clearly rather than falling back to an attachment.


### Table-facing grasp v2

New Physical finger grasp selections use `{action: "grasp", version: 2, target_id: "ball"}`. The performer stands to the side of the table, faces the sphere, and reaches in front of the body. This corrects v1's frontal-camera staging, which placed the sphere behind the character. V1 source/fingerprints remain available for existing takes; new v2 takes use a separate driver and biped revision.

The arm solver rejects a wrist or elbow behind its shoulder plane and keeps the existing reach/flexion limits. Native acceptance measures facing against the sphere and both elbow/wrist front-plane margins at every frame. Profile artwork follows the body direction. A downward head nod and a downward pupil shape draw attention to the near handling target, preserving the blink and speech shapes. This stylized head/pupil treatment is not a calibrated general eyeball gaze solver; the earlier independently aimed attention system remains separate. The ball/finger contact simulation, mass, force limits and free release are unchanged.

### Directed pedestal pickup v3

Choose **Pedestal pickup · acting beats** in Performed Short, with **Template cameras and cuts**. It selects scene setup `grasp_acting` and `{action: "grasp", version: 3, target_id: "ball"}`. V1 and v2 source files/fingerprints remain intact. The character is quietly focused, already facing the pedestal, with bent knees and the left hand prepared to handle a light 200 g ball. The 9 cm sphere starts on a 36 × 40 cm top at 0.955 m; the action arc is register → reach → grip → test weight → lift → assess → replace → release → withdraw → settle. The action stays eight seconds at 12 fps.

| Time (seconds) | Directed action |
| --- | --- |
| 0.00–0.17 | Establish downward pupil/head attention on the ball. Begin chest expansion and a 6 mm forward hip commitment; feet stay planted. |
| 0.25–1.25 | Reach toward the ball after the gaze lead. Body-relative elbow/wrist limits keep the arm in front of the shoulder. |
| 1.25–1.83 | Close the opposed thumb and finger links with 40 ms finger offsets and 25 ms joint offsets, using capped motor torque. |
| 1.83–2.25 | Take weight with a 2–8 mm palm rise and a 1 mm resistance-check pulse; the prop moves only through contact forces. |
| 2.25–3.00 | Raise the ball to roughly 15 cm clearance. Maintain attention on the load. |
| 3.00–4.50 | Sustain a 2 mm vertical/2 mm lateral hand loop. Index/middle targets add 0.018 rad during 3.25–3.75; thumb targets add 0.010 rad during 3.58–4.00. The solver determines the actual finger motion under torque/contact limits. Chest, body height and lateral hip position continue changing. |
| 4.50–5.50 | Lower onto the pedestal before opening the grip. |
| 5.50–6.17 | Release fingers in sequence; thumb release starts at 5.75. Confirm placement with the gaze. |
| 6.17–6.58 | Clear the sphere by moving the open hand 7 cm away from it, lifting 1.2 cm. This clearance precedes the sideways arm retreat so the fingers do not swipe the ball. |
| 6.58–7.50 | Retract the hand toward its preparation area. Ease the body upward by 2.5 cm starting at 6.17. |
| 6.83–7.00 | One blink after clearance, with its peak at 6.92. |
| 7.00–8.00 | Reduce pupil offset and head angle, with the head recovery delayed one frame behind its cue. End at about 12° downward head angle. Breathing and a 1.5 mm lateral weight shift remain active through the last frame. |

Breathing uses unequal keyed intervals: the first inhale peaks at 1.08 s, the first exhale reaches its low point at 2.83 s, then peaks at 3.75/6.50 s and low points at 5.58/7.83 s. Chest scale varies by up to 0.6%; body-height breath motion spans about 3 mm. The hip shift and chest/head timing use one deterministic timeline; no fresh random jitter is generated on a retry or a camera cut. Wide/hand close-up/assessment profile coverage cuts at frames 1, 16, 37, 55 and 75 without restarting the performance.

The v3 pedestal contact profile enables six-dimensional contact with a 2 mm rolling-friction length. This lets the placed sphere lose residual spin through contact instead of adding a freeze or attachment. The profile is pinned with the driver.

V3 owns its gaze timing; competing attention inputs are rejected and the separate attention selector is disabled. The native source embeds per-frame acting states, the four named beats, contact samples and limits. Existing source-bound facial/voice controls remain available. The visible gaze treatment remains a stylized head/pupil drawing control, not a calibrated eyeball simulation. Proxy artwork and this bounded hand/IK model do not establish indistinguishable human performance.

Acceptance retains the measured free-load lift, torque, ground/wrist continuity, forward shoulder-plane limits and pedestal/environment checks. It additionally checks hand/forearm/load clearance against the core body, actual ball movement at every sampled hold frame, actual finger adjustment under contact, chest/hip/body changes and head recovery. Intentional finger/ball and palm/table contacts retain their existing sub-2 mm solver tolerance; other detected intersections fail. Solver checks include weak-grip failure, support before opening, an open withdrawn hand and repeatability. These are sampled native-frame checks, not a proof of collision freedom at arbitrary retimed subframes.


## Validated pickup action v4

Choose **Pick up, inspect and return** in Studio Create → Performed Short. Build a contact performer or select Cast registered with `contact_biped` version 1. The action uses one continuous weighted `ContactHand` mesh, 15 finger joints and `ContactRig`; it does not create a new hand mesh each frame. The source is reusable and its joint keys remain editable.

The optional direction **Pick up the ball, inspect it, and put it back.** selects this reviewed action. It does not synthesize arbitrary mechanics or infer safe parameters for other objects. Nevaeh can submit the same typed `studio.workspace.character.scene.prepare` request with `action_prompt`, the authorized scene/site and a request key. Existing Gatekeeper, ownership, queued status, retry, private preview and Dymond Bank quote/export paths remain authoritative. This action needs no Genesis, ComfyUI, CUDA or speech service.

The calibrated set is a 75 kg adult and a free 200 g, 9 cm sphere on the specified pedestal. The silent performance lasts exactly eight seconds at 24 fps: commit 0–0.25; reach/grip 0.25–1.85; take weight/lift 1.85–3.25; assess 3.25–4.50; place/unload 4.50–6.25; disengage/recover 6.25–8.00. Camera cuts share one world-state timeline. Breathing, gaze, grip feedback, support-before-release and footprint-clear-before-withdraw remain part of the pinned driver.

This action has a bounded ten-minute CPU preview budget (the performed scene remains eight seconds). Other short previews retain their existing budget. The CPU solver requires the pinned MuJoCo, NumPy and SciPy runtime in both Studio media and workstation images. Rebuild those images when deploying this change. Missing dependencies, a changed implementation fingerprint, incompatible Cast, altered prop dimensions, extra obstacles or failed physical/mesh checks block rendering; there is no attachment fallback. Queued takes freeze the implementation fingerprint. Prepare a new take after implementation changes. Previous v1–v3 actions retain their original implementations.

This is a bounded production action. Whole-body checks use centroidal inverse dynamics and per-foot contact-wrench feasibility, alongside articulated hand/contact simulation; they are not a full muscle-driven human simulation. Different character proportions, masses, materials and props require a separately reviewed calibration. Local acceptance and preview receipts do not establish production deployment or live PWA execution.
