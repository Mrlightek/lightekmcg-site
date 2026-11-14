# Reusable music patterns and playlist

Open **Studio → Music → Patterns & playlist**. This extends the existing channel rack, drum machine, piano roll, sampler and mixer. Musical source remains saved with the production, and the song mix uses the existing media-library/edit handoff.

## Write and arrange

1. Click **New empty pattern**. Pick an instrument channel and write its notes using the drum grid or piano roll above. One pattern can contain notes for several channels.
2. Name the pattern and choose its length, from one to sixteen bars. Previous/next and copy/repeat operate within that pattern while it is selected.
3. Choose **Place at song bar**, then **Place linked pattern**. Playlist bars are one-based in the UI and zero-based in saved source.
4. Set each placement's repeat count, transposition, strength or mute state. Duplicate places an independent reference immediately after the selected placement. Remove deletes that placement without deleting its pattern.
5. Select the pattern again to edit its notes. Every placement references the same pattern, so edits update all of them. Duplicate the pattern first when you want a separate variation.
6. Save music. Choose **Song notes · free arrangement** to audition the whole song. In pattern mode, Play auditions that pattern locally. WAV, stems, MIDI and **Add mix to edit** always use the song arrangement.

Free song notes continue to work as before. **Copy free song bar into pattern** copies notes that start in the current free-song bar and trims them at its boundary. It retains the original notes and initially suggests the next song bar for placement. It does not flatten other linked placements into a new pattern. Placing the captured copy over the original channel/pitch produces an overlap error; move the placement or clear the free notes.

Patterns share the song's instrument channels, samples, volume, pan, mute/solo, filter and delay settings. Changing an instrument or its mix affects all patterns using that channel. Removing a channel also removes its notes from patterns; Undo can restore the edit. Deleting a pattern removes its linked placements, also with Undo support.

The song grid includes notes from active placements; click its bars/cells to return to free-song editing. Choose the source pattern in the pattern selector to edit linked notes. A playlist reference is not silently converted into free notes.

## Playback and export

The same deterministic pattern expansion feeds Tone.js live playback, offline 48 kHz stereo WAV rendering, selected-channel stems and MIDI export. Placements repeat at their scheduled bars; melodic transposition changes pitch, while drum mappings retain their original sounds. Strength scales note velocity from 0–1. Muted placements are excluded from the arranged audio and MIDI note expansion. Existing per-channel mix mute/solo behavior remains unchanged.

Editing linked notes while the selected musical context plays uses the existing live scheduling updates. Switching between pattern and song editing stops playback so the context remains clear. WAV/mix exports include only patterns placed in the song; unplaced library patterns remain editable source. MIDI contains expanded song notes and tempo, not the pattern library, custom samples, synthesizer sound or mixer effects. Reimported MIDI therefore becomes free editable notes. The saved Studio music source retains patterns and placements.

**Add mix to edit** saves, renders and uploads the song mix, then uses the existing score placement workflow. Later bounces replace that score's linked audio while retaining its edit position and mix. The new arrangement does not replace the video timeline or claim automatic picture-sync playback; soundtrack placement remains in Edit.

## Source format and bounds

Pattern-free version 1 projects continue to load, play and save. Creating a reusable pattern upgrades the musical source to **version 2**. An older server that supports only version 1 rejects this format rather than silently dropping the pattern bank. Deployment updates the Dashboard asset versions and PWA shell cache together with the server code.

Version 2 retains global `tracks` and their free `notes`, and adds:

| Source field | Meaning |
| --- | --- |
| `patterns[].id`, `name`, `bars` | Stable pattern identity, label and local bar length |
| `patterns[].tracks[].track_id` | An existing global instrument channel |
| `patterns[].tracks[].notes` | Quarter-note timing relative to the pattern start |
| `playlist[].pattern_id` | Source pattern reference |
| `playlist[].bar`, `repeat` | Zero-based song bar and repetition count |
| `playlist[].transpose` | Integer semitones, −24 through +24; melodic channels only |
| `playlist[].velocity`, `muted` | Strength scale and placement mute |

Limits: sixteen channels, thirty-two patterns, 128 placements, one to sixteen bars per pattern, one to thirty-two repeats, 4096 source notes across free notes and pattern definitions, and 16384 notes after expansion. The existing song limits remain 1–128 bars, 40–240 BPM, 4/4 meter and ten minutes. Invalid references, fractional bars/repeats, out-of-song placements, out-of-range transposed pitches and duplicate audible notes on the same channel/pitch are rejected. Muting does not bypass timing, pitch or expansion-size validation.

Source and samples are checked against the authenticated site. Scene locking protects saves, and copied show/episode projects receive independent pattern/placement data. Existing instrument, recording, sampler, MIDI and bounce paths are retained.

Focused checks cover server persistence, bounds, independent copies, linked editing and UI operations, plus actual Tone.js PCM generation at both repeated pattern times and silence for muted placements. Song-level [parameter automation](music-automation.md) is available in source version 3. Multibus effects, extended recording workflows and synchronized picture monitoring remain further music-production work. Integrated production acceptance stays in the final verification sprint.
