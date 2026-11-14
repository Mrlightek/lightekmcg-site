# Music automation

Open **Studio → Music → Song automation**. Select an instrument channel, then choose Volume, Pan, Low-pass or Delay. Automation controls the channel's actual audio parameters in Tone.js, in both song playback and offline mixes/stems. It uses musical beats, so tempo changes preserve its placement relative to notes and linked patterns.

## Shape a song

1. Choose the channel and parameter. The panel shows its current envelope across the full song.
2. Enter **Song beat** (the first beat is 1), a value and an arrival curve, then click **Add automation point**. Fractional beats allow finer timing. The final boundary is song length in beats plus one: beat 17 is the end of a four-bar song.
3. Edit points directly in the list. **Linear** ramps from the preceding point to this one; **Hold** keeps the preceding value until this point, then changes it. Before the first point, a linear arrival ramps from the static mixer value at the song start; a hold arrival keeps that base value. After the last point, its value persists through the audio tail.
4. Rising/falling sweep presets replace this lane's points with a full-song ramp across the parameter's range. Pan presets move between full left and right. Use Undo to recover a previous envelope.
5. **Bypass lane** retains its points while restoring the static mixer value. **Remove lane** deletes this parameter's envelope. Individual points can be removed, too. These edits support Undo/Redo.
6. Save music, then play the song, export a WAV/stem, or **Add mix to edit**. Existing source saves, optimistic scene locking and the media-library/edit handoff remain in use.

Mixer sliders set base values; an enabled lane takes over its parameter. Track mute/solo uses a separate audio gate, so a later volume point cannot unmute a channel. Solo/mute remains authoritative in the song mix; selected stems retain the existing behavior of rendering that channel independently, including its automation. Looping restarts each envelope at song beat 1. Edits to an active envelope cancel its previous future events and schedule the revised curve at the current musical position.

Automation belongs to the **song**, not to a reusable pattern. Editing or moving a linked pattern does not move its channel's song envelope. Pattern audition uses static mixer values so a short phrase does not inherit an unrelated song fade; return to **Song notes · free arrangement** to hear automation. Copying a show template to an episode preserves an independent editable copy of the automation.

## Parameters and limits

| Parameter | Value range | Meaning |
| --- | --- | --- |
| `gain` | 0–1.5 | Linear amplitude; 0 is silence, 1 is unity |
| `pan` | −1–1 | Full left through full right |
| `cutoff` | 100–18000 | Low-pass cutoff in Hz |
| `delay` | 0–0.6 | Wet amount of the existing half-beat feedback delay |

One lane per channel/parameter, at most 64 lanes per song, 128 points per lane and 2048 points in total. Points must have unique beat positions, within the full song including its final boundary. Invalid references, unknown parameters/curves, nonfinite values and out-of-range points are rejected. Bypassing does not skip validation. Shortening the song past existing points is rejected; move/remove those points first. Channel removal also removes its lanes, and Undo restores them with the channel.

## Source and interoperability

Creating automation upgrades source to **version 3**. Version 1 songs and version 2 pattern arrangements continue to load/save without conversion until automation is created. Creating a pattern in version 3 retains that version. Older servers reject version 3 instead of silently dropping automation; deploy the server and Dashboard/PWA assets together.

The source adds `automation: [{track_id, parameter, enabled, points: [{beat, value, curve}]}]`. Saved beats are zero-based quarter notes; point lists are sorted by the server. Song timing, note/sample validation and account/site boundaries still apply. No database migration is required.

WAV, stems and the mix placed into Edit include the audible automation. MIDI export remains notes and tempo; it does not translate these mixer/effect envelopes into MIDI controller messages. Keep the saved Studio source to preserve editable envelopes.

Focused checks exercise source persistence and episode independence, malformed payloads and limits, UI editing/undo/bypass/channel cleanup, plus real audio gain ramps/hold points, stereo pan, filter/delay changes, loop resets, stems and live mute/bypass/edits. Broader mixer buses/effect chains, automation recording, extended recording workflows and synchronized picture monitoring remain further production work. Integrated production acceptance remains in the final verification sprint.
