# Lightek production workstation

## Product contract

The full Studio lives natively in Dashboard. The PWA is a separate client of the same projects and production engines. A creator should be able to finish an episode without moving files between unrelated tools or understanding engine configuration.

The intended product combines professional editing, audio/music production, color, compositing and animation with approachable creation workflows and Lightek's visual identity. Blender supplies 3D authoring, animation, rigs, simulation, physics and rendering. It is one engine in the application. Adding an engine or changing the layout does not establish a complete production workflow by itself.

The character target is film-style animation: recurring identities, editable rigs, body motion, expressive facial performances, dialogue/lip sync, scene staging and finished shots. AI generation belongs inside the same production and should execute on Lightek-managed infrastructure. A prettier viewport or basic toon starter does not satisfy those acceptance criteria. See [AI Studio status](ai-studio.md) for what is and is not implemented.

The interaction model is Photoshop-style layers and compositing, After Effects-style timeline/motion, and Illustrator-style drawing and shape manipulation controlling Blender underneath. Users select and manipulate elements on the canvas; the inspector follows selection and the timeline shows animation. Reusable ready-made characters, sets and effects are first-class starting assets. A client must be able to complete a basic scene without understanding how the engines connect.

The creator's additional content reference is [thememecausus](https://www.instagram.com/thememecausus/), whose public profile describes cinematic 3D animation and political satire. Individual reels were behind Instagram sign-in during review, so their exact visuals and timing have not been assessed. The product acceptance target is a complete original character-led short: reusable cast, staged shots, directed movement and expressions, synchronized dialogue, composited graphics, music, captions and an export, all from the same Lightek production. The [Rain and Snow starter](starter-cast.md) supplies the initial native cast and scene; it does not establish completion of that production target.

## UX rules

- Keep the work visible: picture and timeline in editing, instrument notes and arrangement in music.
- Show the controls relevant to the selection. Deeper sound design, rig bindings and render settings belong behind deliberate choices.
- Use readable language, keyboard access, reversible edits, sensible defaults and useful empty states.
- Use the Lightek black/charcoal, warm gold and restrained blue sound/clip accents. Color supports selection and timing, rather than replacing labels.
- Production templates create editable project structure: scenes, cast, shots, media tracks, music source and delivery settings. Creating an episode makes an independent copy.

Start with the [Media Studio editor](media-workbench.md), [connected production workspace](connected-workspace.md) and [music quickstart](music-quickstart.md) for the implemented workflow.

## Native Dashboard foundation implemented in this change

The workspace route renders `studio-root` within Dashboard; it does not load the PWA document in an iframe. Shared authoring, media, performance, viewport and music modules run in that host. The host supplies authenticated Dashboard execution, uploads and selected-application asset routes. User, application and origin are supplied by the server. PWA routes and clients remain available separately.

The new music workspace stores a versioned musical composition in scene settings, so the existing project/template copy pipeline carries it into independent episodes. It includes:

- A drum step grid, piano roll and bar arrangement for up to 16 instrument tracks.
- Built-in synthesized drums, bass, keys, lead and pad; pitched playback of slices from prepared user audio.
- Tempo, 4/4 bars, sixteenth-note swing, note durations and velocities, mute/solo, volume, stereo pan, low-pass filter and delay.
- Undo/redo, source saving with optimistic locking, constant-tempo 4/4 MIDI import/export, stereo WAV mix and individual-track stem downloads.
- A mix bounce that uses the regular upload/ingestion pipeline and places the first ready mix on the episode editing timeline at zero seconds. Later bounces replace that score’s linked audio while retaining its placement, trim and mix controls; whole-source clips adopt the new full mix duration. A shorter new mix that invalidates a source trim is rejected. Its musical source remains editable.

Tone.js 15.1.22 powers both live instruments and offline audio rendering; @tonejs/midi 2.0.28 supplies MIDI interchange. Both are vendored with licenses. The initial bounce is 48 kHz / 16-bit stereo WAV. The existing timeline master exporter can mix audio into its delivery master.

Current limits: 128 bars, ten minutes, 4096 notes per composition, 32 simultaneous synth voices per pitched instrument. Samples use up to 30 seconds of a recording up to two minutes and 25 MB. The initial piano roll writes on a sixteenth-note grid and displays imported notes at their original positions. Imported MIDI uses constant tempo and 4/4; custom drum kit mappings, tempo/meter changes and controller automation are not supported yet. MIDI preserves source notes and tempo, rather than instrument audio, effects, sample mappings or swing settings. Notes, arrangement timing and mix parameters can update during loop playback. Instrument/sample changes and undo/redo stop playback; press Play to resume. Do not describe this release as a complete DAW.

## Remaining music-production work

Live vocal/instrument recording and comping; hardware MIDI input and recording; pattern clips and sections; tempo/meter maps and picture cue markers; automation lanes; richer sampler/instrument engines and sound banks; inserts, sends, buses, EQ, dynamics, reverb and metering; nondestructive sample chopping/time-stretch; 24-bit and float source bounces; bulk aligned stem packages; score templates with scene synchronization. Professional plugin hosting requires a worker/plugin architecture, not an unsupported claim that arbitrary desktop plugins run in the browser.

## AI shows and digital cast remain in scope

Support the creator playing multiple roles, original digital characters, licensed cast likenesses, facial performance transfer, face replacement, lip sync, and compositing those performances into Blender sets and edited footage. Generated shots must become normal versioned production assets, editable and usable alongside recordings, animation, physics, simulation and music.

The following are researched candidates, not installed or integrated engines:

| Candidate | Relevant function | Integration constraint |
| --- | --- | --- |
| MuseTalk | Audio-driven lip sync | Its README permits commercial use of code and trained models; every bundled dependency/checkpoint must retain its own applicable license. |
| LivePortrait | Facial performance animation | The MIT code license explicitly requires replacing the included noncommercial InsightFace detection models for a commercial setup. |
| FaceFusion | Face manipulation/replacement | Code and individual assets have separate licenses. Default or optional noncommercial models cannot silently become the production stack. |

Sources checked 2026-11-11: [MuseTalk README](https://github.com/TMElyralab/MuseTalk), [LivePortrait license](https://github.com/KlingAIResearch/LivePortrait/blob/main/LICENSE), [FaceFusion model licenses](https://docs.facefusion.io/introduction/licenses).

A real integration must pin an eligible code/model/dependency set, provision it through the existing instance/update pipeline, run bounded jobs on a suitable media worker, show actual progress and failures, and save the resulting shots with their production source references. No face-model downloads or AI-show rendering are implemented by this music change.

## End-to-end acceptance target

Create a production template → create an independent episode → import/record footage and dialogue → direct digital characters → render/composite Blender shots and simulations → write original music against picture cues → edit, grade and mix → export and publish the episode. Each phase uses the same production assets, versions and timing references. "Better" is demonstrated by that connected workflow, not by the number of panels or dependencies.

Native Dashboard browser checks now cover the shared production and music screens at 1440, 1024 and 390 pixels: note creation, source saving, return to production, no iframe, no page overflow and no JavaScript exceptions. The phone layout stacks the instrument selector, editor and mixer. These checks use a scoped API fixture; Rails integration checks separately cover authorization, CSRF, uploads, source/template isolation and linked mix placement. Actual authenticated production review, device audio playback and media-worker operation remain deployment acceptance steps.

Run `node test/javascript/studio_dashboard_browser_test.cjs` with Playwright Chromium installed; optional `STUDIO_CHROMIUM_EXECUTABLE` selects an existing binary. Screenshots are written to `tmp/studio-dashboard-browser/`. Music source/transport checks run with `BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/studio_music_checks.rb --name /test_music_/`. Interaction and native Web Audio tests are `studio_music_ui_test.cjs` and `studio_music_audio_test.cjs` in `test/javascript`.
