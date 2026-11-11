# Lightek production suite: production scores and finishing

## Start with a production, not an empty scene

Open **Studio → Templates**. The chooser now includes the original JSON media packs alongside eight original Lightek production packages. Choose a production name and **Create production from template**. Existing projects stay intact; the new project has independent scenes, a Production record and reusable scene settings.

| Package | Planned running time | Scene setups |
| --- | ---: | ---: |
| Lightek Police Procedural starter | 4 min 10 sec | 8 |
| Network Procedural | 42 min | 35 |
| Ensemble Comedy | 22 min | 22 |
| Family Adventure | 22 min | 22 |
| Serialized Drama | 48 min | 40 |
| Documentary | 30 min | 30 |
| Live Concert | 30 min | 30 |
| Music Video | 3 min | 6 |

These are original formats built around genre conventions, not adaptations of another network's characters, scripts, branding or music. The running time is the sum of planned scene durations, not a finished rendered episode.

Each new Lightek package supplies:

- A timed scene structure and scene objectives.
- Four editable camera setups with focal lengths and timed coverage.
- Editable blocking geometry, lighting and performer placeholders.
- Lightek title branding and 1080p/24 fps starting settings.
- Dialogue, room tone, Foley, score and effects mixer tracks.
- Music cue sheets with entrances/exits, tempo, meter, instrumentation, dynamics and sync direction.
- Timed performance cues and a scene plan visible in the workspace.
- Native Blender camera cuts and music markers saved into the rendered `.blend`.

The complete starting definition lives on the Production record. Each scene retains its own relevant score and source checksum. A request receipt makes retrying project creation safe. **Save as template** copies the production, scenes, native sources and direction for future projects.

### Example: build an original police procedural

1. Choose **Lightek Police Procedural** in Templates and name your pilot.
2. Open the cold-open scene. Read **Production plan** for its objective, shot timings and music cues.
3. Inspect the Master wide, Investigator single, Witness reverse and Evidence insert cameras. Adjust lenses, transforms and lights. Existing native Blender authoring and the full Blender workstation remain available.
4. Replace the blocking characters and sets with your assets. Import recorded performances, dialogue and music through Library.
5. Render a Blender movie shot through the existing quote/payment/render workflow.
6. In Delivery, use **Use in edit library** on the completed render. Preparation is queued once; the source attachment is reused without another upload.
7. Add the prepared shot to Timeline. Arrange it with dialogue, Foley, score and graphics.
8. Export an MP4 review/delivery copy or a ProRes master. Publish the MP4 through the existing community/OTT workflow.

The cue sheet is a production and composition plan. It does not synthesize or supply recorded music, vocals, actors or finished footage. Match actual recorded music to its real tempo; adjust the creative direction and camera setup in the saved project. The native `.blend` Text Editor contains the scene's JSON score for detailed changes. The web plan panel currently displays those directions; a dedicated visual cue-sheet editor remains future work.

## Edit and finish

Timeline and Audio share one sequence. Add prepared video, image and audio assets. New clips append to the sequence; change **Timeline start** and **Track** to layer them. Click a track bar to select its clip.

- Move the playhead to a frame and split the selected clip. Source timing accounts for playback speed, and boundary position/volume keyframes are preserved.
- Duplicate, trim or remove a clip. Undo/redo keeps up to 60 in-session edits; saved timelines persist with scene version checking.
- Set playback speed from 0.25× to 4×. FFmpeg uses pitch-preserving tempo processing for audio.
- Set picture position, scale, opacity, brightness, contrast and saturation. Position and gain keyframes remain available.
- Set clip fades. Layer overlapping footage and fade its opacity for a dissolve; fade audio clips for a crossfade.
- Name tracks, adjust gain/pan, mute or solo audio tracks. Solo/mute does not hide their pictures.
- Apply a low-cut filter or export noise reduction to a clip.
- Add timed titles or caption lines with text, position and size.

**Save timeline** persists edits. **Export quote** saves first and enters the existing checkout/render queue. Saving or selecting a template does not start payment, publishing or a live broadcast.

| Output | Review/delivery | Master |
| --- | --- | --- |
| Video | H.264 MP4, AAC 320 kb/s | ProRes 422 HQ MOV, 24-bit PCM |
| Audio | 16-bit PCM WAV | 24-bit PCM WAV |

Audio exports use 48 kHz stereo. Frame rates: 24, 25, 30, 48, 50 or 60. Even output dimensions: 64–4096 pixels, including 3840×2160. MP4 remains the OTT publishing format; a ProRes MOV is an intermediate master.

Browser playback is a proxy, not a color-managed reference monitor. Final FFmpeg output is authoritative for color, denoising and limiting. The preview supports timeline timing, gain, pan, low cut, fades, picture transforms and titles, with approximate browser color controls.

## Operational limits and unfinished work

The finishing engine allows 64 clips, 16 tracks, 32 titles and 20 keyframes per clip, with a ten-minute assembly/source window. Full-length template plans span multiple scenes. They do not yet create a single 22–48 minute export: edit short scene/act assemblies independently. Whole-episode conform/export, proxy generation, long-source browsing and chunked renders need a subsequent release. Existing Blender movie-shot exports remain capped at 2400 frames per shot; split longer planned scenes into shots.

This release does not implement a complete DAW, MIDI/instrument sequencing, score synthesis, multitrack recording, automatic music generation, multicam synchronization, automatic dialogue editing, advanced grading/scopes, HDR/ACES, tracking/rotoscoping, surround mixing, collaborative review or production asset relinking. Native Blender tools remain available through the workstation. Hollywood production readiness requires dedicated acceptance for these workflows, long-form reliability and target delivery specifications.

## Deploy and verify

Apply migration `20261111130000_register_studio_production_suite` and restart the application/workers. Normal provisioning/deployment builds the updated `lightek/studio-media:20261111` image, including fonts for text rendering. Overrides of `STUDIO_MEDIA_WORKER_IMAGE` must supply compatible FFmpeg filters, H.264, ProRes, PCM and fonts. The PWA shell cache is v56.

Focused checks:

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/timeline_finishing_checks.rb
BUNDLE_GEMFILE=test/standalone/Gemfile LIGHTEK_TEST_BLENDER=1 bundle exec ruby test/standalone/media_preset_checks.rb --name '/test_production_|test_real_blender_production_score|test_all_recovered|test_presets_create|test_format_and_material|test_idempotency_stale|test_missing_assets/'
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb --name '/test_completed_render_reuse|test_real_media_ingestion_and_keyframed_multitrack_export|test_actual_audio_mix_and_native_ott_publication|test_timeline_rejects_foreign_assets/'
node test/javascript/studio_finishing_test.cjs
python3 -m unittest test.operations.studio_media_setup_test test.operations.studio_worker_limits_test
```

The new DOM test requires `jsdom`; the existing CI job already installs it. It checks editing state and rendered controls, not browser media playback or visual layout. Real FFmpeg tests inspect codecs, sample format, duration and actual stereo output. The Blender check reopens the generated source and inspects bound camera cuts, music markers and Lightek branding, including after a camera is renamed.
