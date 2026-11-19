# Performed character short

Open Studio Create → **Performed Short** in Dashboard or PWA. This guided entry connects existing Cast creation/placement, stock speech, Rhubarb speech analysis, saved performances, native cameras, preview rendering and paid shot exports. It does not require a Genesis connection.

1. Choose **Scene setup**: a plain character stage, the current editable scene set, or an existing library recipe such as Atlanta Night Exterior or Live Interview. The setup supplies editable sets, props and lights. Blocking mannequins are replaced by the selected performer. Select **Template cameras and cuts** to retain authored coverage, or **Frontal wide-to-close coverage** for the illustrated puppet. Choose a starter action or no added gesture.
2. Name the performer. Build an illustrated starter with skin/wardrobe/hair colors, or select an existing registered Cast asset from the library.
3. Enter a short spoken line such as **We protect this city.** Choose the stock US or UK English voice, or select a prepared recording lasting 0.2–2.8 seconds and no larger than 10 MiB. Import recordings through Media Library. The dialogue field can guide analysis of a recording.
4. Choose **Prepare performed short**. Worker phases report character build, dialogue preparation, speech analysis, camera direction and preview rendering. Reloading Studio restores the latest preparation for this creator and source scene. Preparation creates a separate scene in the same project; it does not overwrite the source scene.
5. Watch the three-second private preview. Frontal coverage cuts at 1.5 seconds; template coverage uses its saved cameras/cuts. Speech drives mouth shapes. The selected gesture is used where the rig supplies the binding.
6. Open the editable character scene to change Cast, face/gesture cues, body motion, cameras or scene settings. Saved project/show templates retain this scene, Cast bindings and takes; copying to an episode remaps camera cuts to its copied camera objects. The character remains a reusable Cast asset, and the generated/copied audio remains a separate owned recording.
7. Request the full shot export price. Repeated requests for the same current scene reuse its quote. Checkout, payment settlement, immutable source capture, full MP4/Blender output and failed paid-render recovery use the existing Studio/Dymond Bank paths.

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

The scene is a technical character study toward original episodic animation. Full-body walking/combat choreography, detailed expressions, multiple speakers, arbitrary scene scripts, automatic conversion of layered-compositor backgrounds and production-quality visual review remain further work. No likeness or voice cloning is introduced.

## Execution and recovery

The prepare/status/retry/quote capabilities are `studio.workspace.character.scene.*`. They remain actor/site/project scoped, available through the existing authenticated PWA bridge, and registered by `20261119010000_register_character_scene_workflow`. Template catalog/launch capabilities are registered by `20261119020000_register_character_template_workflow`.

Inputs are bounded: a 1–60 character name, up to 80 dialogue characters, fixed stock voice choices, hex colors and owned source assets. Recorded input bytes are attached to the preparation before queuing; a copied source recording remains frozen. Reused Cast profile/source identity is checked before placement. Changed inputs cannot replay a request key.

Preparation uses the Studio queue. Durable receipts retain the new scene, reusable character, analysis, take and render. Retrying a failed preparation reuses those resources. Competing jobs defer to an in-progress worker; an eleven-minute watchdog marks an expired ten-minute attempt failed, including preparations waiting for another worker. A failure never becomes a successful substitute animation or analysis. Missing eSpeak-ng, Rhubarb or Blender must be fixed on the selected worker; the UI surfaces that failure and a retry action.

The deployed Studio media image already includes stock speech and the pinned Rhubarb 1.14.0 package. Synthesis is local eSpeak-ng; phonetic Rhubarb analysis is offline and should be reviewed against the voice recording. This is not professional voice acting or exact word alignment. Neural voices remain separate optional tools.

Preview rendering uses the existing CPU Economy configuration: one CPU render slot by default, 320-pixel preview edge, 12 fps, three seconds and up to eight samples. Existing character build/import and analysis container limits still apply; this workflow does not establish free memory on a busy 2 GB host. Inspect and measure the intended installation.

## Acceptance

`test/standalone/studio_character_scene_checks.rb` covers actor boundaries, input limits, duplicate requests, retries and quote gating. With `LIGHTEK_TEST_CHARACTER_SCENE=1`, it builds a real illustrated character, synthesizes real speech, runs pinned Rhubarb, saves a phoneme take and camera cuts, renders a three-second MP4, checks audible PCM and reopens the Blender output to inspect changing mouth/bone values, camera switching, packed sound and editable controls. DOM checks cover the Dashboard and PWA flow without Genesis status calls.

The native CI preserves the MP4 and `.blend` proof. Production acceptance still requires a real PWA submission, worker execution, owner review, authorized full checkout and final Timeline/publishing verification. `studio_scene_templates_checks.rb` additionally verifies catalog coverage, production/saved-show creation, isolation, frozen sets, copied model sources and a real rooftop-template performance render. Local test output does not establish completed episode production.
