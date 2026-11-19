# Performed character short

Open Studio Create → **Performed Short** in Dashboard or PWA. This guided entry connects existing Cast creation/placement, stock speech, Rhubarb speech analysis, saved performances, native cameras, preview rendering and paid shot exports. It does not require a Genesis connection.

1. Name the performer. Build an illustrated starter with skin/wardrobe/hair colors, or select an existing registered Cast asset from the library.
2. Enter a short spoken line such as **We protect this city.** Choose the stock US or UK English voice, or select a prepared recording lasting 0.2–2.8 seconds and no larger than 10 MiB. Import recordings through Media Library. The dialogue field can guide analysis of a recording.
3. Choose **Prepare performed short**. Worker phases report character build, dialogue preparation, speech analysis, camera direction and preview rendering. Reloading Studio restores the latest preparation for this creator and source scene. Preparation creates a separate scene in the same project; it does not overwrite the source scene.
4. Watch the three-second private preview. It has a wide-to-close camera cut at 1.5 seconds, speech-driven mouth shapes, and a right-arm gesture where the rig supplies that binding.
5. Open the editable character scene to change Cast, face/gesture cues, body motion, cameras or scene settings. Saved project/show templates retain this scene, Cast bindings and takes; copying to an episode remaps camera cuts to its copied camera objects. The character remains a reusable Cast asset, and the generated/copied audio remains a separate owned recording.
6. Request the full shot export price. Repeated requests for the same current scene reuse its quote. Checkout, payment settlement, immutable source capture, full MP4/Blender output and failed paid-render recovery use the existing Studio/Dymond Bank paths.

## Scope and artwork

The illustrated starter uses flat editable mesh drawings and emission materials, compatible with the existing performer face keys and three pose bones. It is a simple puppet, not detailed production character art, an automatic character designer, a complete human rig or a finished-show quality claim. Existing Cast assets can supply richer authored art and animation through their own bindings. Unbound arm gestures are omitted; speech still requires a registered mouth binding.

The scene is a technical character study toward original episodic animation. Full-body walking/combat choreography, detailed expressions, multiple speakers, arbitrary scene scripts, backgrounds linked from the layered compositor and production-quality visual review remain further work. No likeness or voice cloning is introduced.

## Execution and recovery

The prepare/status/retry/quote capabilities are `studio.workspace.character.scene.*`. They remain actor/site/project scoped, available through the existing authenticated PWA bridge, and registered by `20261119010000_register_character_scene_workflow`.

Inputs are bounded: a 1–60 character name, up to 80 dialogue characters, fixed stock voice choices, hex colors and owned source assets. Recorded input bytes are attached to the preparation before queuing; a copied source recording remains frozen. Reused Cast profile/source identity is checked before placement. Changed inputs cannot replay a request key.

Preparation uses the Studio queue. Durable receipts retain the new scene, reusable character, analysis, take and render. Retrying a failed preparation reuses those resources. Competing jobs defer to an in-progress worker; an eleven-minute watchdog marks an expired ten-minute attempt failed, including preparations waiting for another worker. A failure never becomes a successful substitute animation or analysis. Missing eSpeak-ng, Rhubarb or Blender must be fixed on the selected worker; the UI surfaces that failure and a retry action.

The deployed Studio media image already includes stock speech and the pinned Rhubarb 1.14.0 package. Synthesis is local eSpeak-ng; phonetic Rhubarb analysis is offline and should be reviewed against the voice recording. This is not professional voice acting or exact word alignment. Neural voices remain separate optional tools.

Preview rendering uses the existing CPU Economy configuration: one CPU render slot by default, 320-pixel preview edge, 12 fps, three seconds and one sample. Existing character build/import and analysis container limits still apply; this workflow does not establish free memory on a busy 2 GB host. Inspect and measure the intended installation.

## Acceptance

`test/standalone/studio_character_scene_checks.rb` covers actor boundaries, input limits, duplicate requests, retries and quote gating. With `LIGHTEK_TEST_CHARACTER_SCENE=1`, it builds a real illustrated character, synthesizes real speech, runs pinned Rhubarb, saves a phoneme take and camera cuts, renders a three-second MP4, checks audible PCM and reopens the Blender output to inspect changing mouth/bone values, camera switching, packed sound and editable controls. DOM checks cover the Dashboard and PWA flow without Genesis status calls.

The native CI preserves the MP4 and `.blend` proof. Production acceptance still requires a real PWA submission, worker execution, owner review, authorized full checkout and final Timeline/publishing verification. Local test output does not establish completed episode production.
