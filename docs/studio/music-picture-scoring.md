# Score against picture

Open **Studio → Music → Score against picture**. The monitor reuses the Edit workspace's proxy compositor, driven by the live music transport clock. It can show the current edit's layers, source trims/speed, transforms, fades, picture adjustments and titles while you compose and mix.

## Connect the edit and score

1. Assemble picture in **Edit**, then open Music. Click **Enable picture** to load a snapshot of the current edit, including the open edit draft if one exists. All referenced media must be prepared and accessible in the selected site.
2. Set **Score start in edit · seconds**, or scrub to a picture moment and click **Start score at picture time**. This maps song time zero to that edit time.
3. Play the **song**. The monitor follows score start plus the music transport position, including song loops. The monitor's video/audio elements are muted, and audio-only edit clips are skipped, so an older bounced score cannot double the live score. You hear the current Music channels, recorded takes, automation, groups and master.
4. Edit notes or adjust the mix. Music's own redraw preserves the active canvas; changes that already require an audio graph rebuild stop playback. Loading a different scene or leaving the workspace releases the preview.
5. Use **Refresh edit snapshot** after changing the cut. The monitor does not automatically replace its snapshot in the middle of a scoring pass. **Open Edit** returns to the sequence.

Song playback begins at the score's start, not at the picture scrub position. The picture scrubber and **Preview cue** move picture only. Pattern audition remains local to the selected pattern and does not play the song picture monitor. This sprint does not add arbitrary song seek, pre-roll, synchronized microphone overdub or device-latency compensation.

## Mark picture cues

Scrub to a moment, enter a label and choose **Mark picture cue**. The cue sheet stores edit time in seconds and displays the corresponding musical beat at the current tempo and score start. Moments before/after the song are labelled **Outside score**. Edit labels/times, remove cues, preview them, or use music Undo/Redo. Cues reference picture moments; changing tempo changes their displayed musical beat rather than moving their edit time.

Save music to retain score start and cues. There are at most 64 cues, with stable IDs, 60-character labels and times between 0 and 600 seconds. Score start plus the song's duration must fit the ten-minute edit bound. The final WAV mix tail also has to fit the edit when placed; shorten it or move the start earlier if the existing timeline validator reports an end-bound error.

## Bounce and placement

**Add mix to edit** still saves the source, renders the current mix, imports it and replaces this score's linked audio. The first placement uses the configured score start. An explicitly changed score start moves the linked clip on the next bounce, preserving its trim, gain and other edit settings. If the configured start is unchanged, a manual move made in Edit is retained; the monitor/start field follows that linked clip's actual position. This extends the existing mix replacement behavior without overwriting unrelated timeline clips.

WAV and processed-stem downloads remain song-relative audio files. Cue markers and the picture itself are not baked into those audio downloads. Use the regular Edit export to render the production with picture and its placed soundtrack.

## Preview contract

The music transport supplies the reference clock. Active video elements seek back when they drift by more than 80 ms, including after loops or picture scrubs. Source in points and playback speed map to that clock; portrait/square edits are letterboxed rather than stretched. Picture monitoring does not create an audio context or move the Edit workspace's playhead, mutate its timeline, or emit Edit playhead events.

This is a browser proxy monitor, not a frame-accurate finishing guarantee. Media decode, browser scheduling and hardware affect visible timing. Final exports use the existing production render pipeline and apply full supported processing. Missing/preparing references produce an error instead of a fabricated picture. Native permission/site boundaries remain in use; exact asset-reference lookup is limited to 64 IDs and forces the authenticated site.

## Saved source and verification

Creating/editing scoring metadata upgrades source to **version 6**, adding `scoring: {start, cues: [{id, name, time}]}`. Source versions 1–5 remain supported, and adding patterns/automation/mixer controls/audio takes does not downgrade a scored project. Template-to-episode copies retain independent cue settings. No database migration is required; deploy the updated compositor/music scripts and PWA cache with the server.

Focused checks cover source bounds, independent copies, exact-reference isolation, first and replacement mix alignment, UI clock mapping/cue persistence/canvas preservation, and the shared compositor's muted external clock, trim/speed, drift, loop reset, pause and cleanup. A decoded-video/real-music browser check is included in CI alongside the existing Edit acceptance check. Local Chromium execution was blocked by this workspace's socket restrictions, so those browser checks were not run here. Device/browser timing and integrated scoring/capture/export remain part of the final production verification sprint.
