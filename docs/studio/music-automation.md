# Music automation

Open **Studio → Music → Song automation**. Choose **Automation destination**: the selected instrument channel, a mixer group or the master mix. Channels support Volume, Pan, Low-pass and Delay; groups support Volume and Pan; Master supports Volume. Automation controls the actual audio parameters in Tone.js, in both song playback and offline mixes/stems. It uses musical beats, so tempo changes preserve its placement relative to notes and linked patterns.

## Shape a song

1. Choose the destination and parameter. Create groups and route channels under **Mixer buses & inserts** before choosing a group here. The panel shows its current envelope across the full song.
2. Enter **Song beat** (the first beat is 1), a value and an arrival curve, then click **Add automation point**. Fractional beats allow finer timing. The final boundary is song length in beats plus one: beat 17 is the end of a four-bar song.
3. Edit points directly in the list. **Linear** ramps from the preceding point to this one; **Hold** keeps the preceding value until this point, then changes it. Before the first point, a linear arrival ramps from the static mixer value at the song start; a hold arrival keeps that base value. After the last point, its value persists through the audio tail.
4. Rising/falling sweep presets replace this lane's points with a full-song ramp across the parameter's range. Pan presets move between full left and right. Use Undo to recover a previous envelope.
5. **Bypass lane** retains its points while restoring the static mixer value. **Remove lane** deletes this parameter's envelope. Individual points can be removed, too. These edits support Undo/Redo.
6. Save music, then play the song, export a WAV/stem, or **Add mix to edit**. Existing source saves, optimistic scene locking and the media-library/edit handoff remain in use.

Mixer sliders set base values; an enabled lane takes over its parameter. Channel, bus and master envelopes are separate stages: their gains multiply. Group pan acts on the summed group. Track/group mute and solo use separate audio gates, so later volume points cannot unmute a channel or group. Solo/mute remains authoritative in the song mix; selected stems retain the existing behavior of rendering that channel independently, including its channel, group and master automation. Looping restarts each envelope at song beat 1. Edits to an active envelope cancel its previous future events and schedule the revised curve at the current musical position.

Automation belongs to the **song**, not to a reusable pattern. Editing or moving a linked pattern does not move any song envelope. Pattern audition uses static mixer values so a short phrase does not inherit an unrelated song fade; return to **Song notes · free arrangement** to hear automation. Copying a show template to an episode preserves an independent editable copy of the automation.

## Group and master workflow

For a music bed under dialogue, route the musical channels to a Music group. Select that bus under **Automation destination**, choose Volume, add hold/ramp points where the bed should fall and rise, then save the song. For an end fade across the production mix, choose Master mix → Volume and add a falling envelope. These are hand-authored envelopes, not automatic sidechain ducking.

Use the same point editor, sweep presets, graph, bypass and Undo/Redo for all destinations. Edits, bypass and base fader changes update during playback; loop playback restarts envelopes at song beat 1. An enabled lane remains authoritative over its base fader. A bypassed lane uses the current base value while keeping its points.

Removing a bus reroutes its channels to Master and removes that bus's envelopes and inserts. Undo restores the routing and envelopes. Channel removal only removes its own lanes. Template episodes retain independent copies. Pattern audition keeps routing and static bus/master faders while excluding all song automation.

Selected-channel stems include group/master envelopes and processing. Their existing isolated-source mute/solo bypass still applies; a master fade to silence also silences the processed stem. WAV and **Add mix to edit** use the same scheduling and final limiter. MIDI remains notes and tempo.

## Parameters and limits

| Parameter | Value range | Meaning |
| --- | --- | --- |
| `gain` | 0–1.5 | Linear amplitude; 0 is silence, 1 is unity |
| `pan` | −1–1 | Full left through full right |
| `cutoff` | 100–18000 | Low-pass cutoff in Hz |
| `delay` | 0–0.6 | Wet amount of the existing half-beat feedback delay |

One lane per destination/parameter, at most 64 lanes shared across channels, groups and master per song, 128 points per lane and 2048 points in total. Points must have unique beat positions, within the full song including its final boundary. Invalid references, unknown parameters/curves, nonfinite values and out-of-range points are rejected. Bypassing does not skip validation. Shortening the song past existing points is rejected; move/remove those points first. Channel removal also removes its lanes, and Undo restores them with the channel.

## Source and interoperability

Creating channel automation requires source **version 3** or later. Creating group/master automation upgrades source to **version 7**, retaining mixer, patterns, recordings and picture settings. The Dashboard initializes the mixer and preserves the effective picture start when upgrading a source that had no explicit scoring settings. Version 1 songs and version 2 pattern arrangements continue to load/save without conversion until automation is created. Creating a pattern in version 3 retains that version. Older servers reject version 3 instead of silently dropping automation; deploy the server and Dashboard/PWA assets together.

Each entry in `automation` has exactly one target: `track_id` for a channel, `bus_id` for a group, or `master: true`. It also stores `parameter`, `enabled` and `points: [{beat, value, curve}]`. Channel and bus IDs may coincide; target type is part of lane identity. Missing/ambiguous targets, master pan and group filter/delay lanes are rejected. Group/master lanes require version 7 even when bypassed. Earlier source versions 1–6 remain supported; older servers reject version 7 rather than dropping envelopes. Deploy server and Dashboard/PWA assets together. Saved beats are zero-based quarter notes; point lists are sorted by the server. Song timing, note/sample validation and account/site boundaries still apply. No database migration is required.

WAV, stems and the mix placed into Edit include the audible automation. MIDI export remains notes and tempo; it does not translate these mixer/effect envelopes into MIDI controller messages. Keep the saved Studio source to preserve editable envelopes.

Focused checks exercise source persistence and episode independence, malformed payloads and limits, UI editing/undo/bypass/channel cleanup, plus real audio gain ramps/hold points, stereo pan, filter/delay changes, loop resets, stems and live mute/bypass/edits. Ordered [mixer buses/effect chains](music-mixer.md) are available in source version 4. Group/master fader automation is available in source version 7. Insert-parameter automation and automation recording remain further work. [Picture scoring](music-picture-scoring.md) and [microphone overdub](music-overdub.md) are available through the shared song workflow. Focused checks cover group/master persistence, template independence, target collisions and rejection/budgets, UI cleanup/undo, real PCM hold/ramp/pan and gain multiplication, processed stems, loop resets and live edit/bypass/mute behavior. Integrated production acceptance remains in the final verification sprint.
