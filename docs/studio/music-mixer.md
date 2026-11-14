# Mixer buses and effect inserts

Open **Studio → Music → Mixer buses & inserts**. This extends the existing channel rack, patterns, song automation, sampler and production mix handoff with shared instrument groups and ordered processing.

## Route and mix

1. Click **Add mixer bus**, then name the group, such as Drums, Strings or Dialogue samples. A bus sums its assigned channels.
2. Expand **Channel routing**. Route each instrument to a group or directly to Master. Channels have one output; groups feed Master directly. No nested buses or feedback routing is introduced.
3. Select **Edit processing** to edit the selected instrument channel, a bus, or the master. Channel faders/pan remain in the existing Track mixer; bus and master faders appear here. A bus also has pan and mute/solo controls.
4. Choose an insert. Adjust its parameters, bypass it with **Active**, reorder it with **Move up/down**, or remove it. Inserts run top to bottom. Source saves preserve their order, settings and bypass state.
5. Play the pattern or song, save music, export a WAV/stem, or use **Add mix to edit**. These use the same audio routing. Pattern audition retains routing/inserts but omits the song automation, as before.

Routing and insert changes stop playback because they rebuild the processing graph. Press Play to hear the revised graph. Bus/master faders, bus pan and mute/solo update during playback. Undo/Redo restores routes, deleted groups and their effects. Removing a group returns its channels directly to Master; the button names this behavior explicitly.

## Signal path

Channel instrument → existing low-pass/delay controls → channel inserts → channel pan/gain and mute gate → selected bus inserts/pan/gain/mute gate (if routed) → master inserts/gain → existing final −1 dB limiter.

Channel automation continues to control its own gain, pan, filter and delay before the bus. Bus and insert parameter automation is not part of this sprint. Group mute gates the processed group, including delay tails; later channel automation cannot unmute it. Bus solo excludes direct-to-master channels and other groups. Existing channel solo and group solo are intersected: a channel must pass both selections. Mute remains authoritative.

Selected-channel stems silence all other instrument sources while retaining that channel's group and master processing. As with the existing track-stem behavior, channel/group mute and solo are bypassed for the selected source. Group/master fader levels still apply. These are **processed stems**: summing individually exported stems through nonlinear group/master compression or distortion does not necessarily reconstruct the full mix. They are not dry multitrack exports.

## Included inserts

| Insert | Controls | Bounds |
| --- | --- | --- |
| Three-band EQ | Low, mid, high gain | −24 to +24 dB; fixed Tone.js crossovers |
| Compressor | Threshold, ratio, attack, release, knee | −60–0 dB; 1–20; 0.001–1 s; 0.01–1 s; 0–40 dB |
| Distortion | Drive, wet mix | 0–1 each |
| Feedback delay | Time, feedback, wet mix | 0.01–1 s; 0–0.75; 0–1 |

These are the existing vendored Tone.js processors, not placeholder controls. The Web Audio compressor includes automatic makeup gain; compression reduces dynamic range rather than guaranteeing a lower output level. Delay insert time is in seconds, independent of the existing channel's tempo-following half-beat delay.

Exports add an estimated decay tail for enabled delay inserts on each channel's route, with up to thirty seconds of additional audio and the existing ten-minute total cap. Long decays may be cut at those bounds. Muted/bypassed processing and the final limiter follow the same routing in monitoring and offline renders. The regular source save and media-library/edit replacement workflow remains in use.

## Saved source and bounds

Mixer configuration upgrades musical source to **version 4**. Versions 1–3 remain supported; adding automation or patterns to a version 4 song retains version 4. An older server rejects version 4 rather than dropping mixer data. Deploy server code with the updated Dashboard assets and PWA cache. No database migration is needed.

- Global tracks add `bus_id` (null for Master) and ordered `effects`.
- `mixer.buses` stores `{id, name, gain, pan, muted, solo, effects}`.
- `mixer.master` stores `{gain, effects}`.
- Each insert stores `{id, kind, enabled, params}`. Supported kinds are `eq`, `compressor`, `distortion`, `delay`.

Limits: eight groups; four inserts per channel, group or master chain; thirty-two inserts total, including bypassed inserts. Existing sixteen-channel, note, pattern and automation limits remain. Bus IDs and per-chain insert IDs must be unique. References, switches, parameters and numeric ranges are validated on the client and server. Unknown processors/parameters, missing buses and attempted bus-to-bus routing are rejected. Authenticated scene/site ownership and optimistic save locking remain enforced. Template-to-episode copies retain independent mixer data.

MIDI export remains notes and tempo; it does not encode these effect chains or routing. Retain the saved Studio source for editable processing, or export WAV/stems for the audible result.

Focused checks cover save normalization, bounds and malformed payloads, episode independence, coexistence with patterns/automation, UI routing/reordering/bypass/undo, plus actual DSP for faders, pan, mute/solo, processed stems, EQ, compression, distortion, delay, order changes, tails and live controls. Sends/returns, nested routing, sidechain controls, bus automation, additional effects, recording and picture synchronization remain further production work. Integrated production acceptance remains in the final verification sprint.
