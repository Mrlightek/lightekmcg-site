# Recording and audio takes

Open **Studio → Music → Record & place audio takes**. Microphone capture is local until you explicitly save it. A saved take can become an original-pitch audio channel in the song, through the same automation, inserts, groups and master mix as instrument channels.

## Record, review, save and place

1. Click **Record microphone** and grant your browser microphone permission. Capture requests audio only, with echo cancellation, noise suppression and automatic gain control disabled where the browser supports those constraints. The operating system's default microphone is used.
2. Speak, sing or record a sound. The timer shows elapsed recording time. The RMS/peak readout measures actual microphone samples; peaks at or above 0.98 are marked as clipping. If the browser cannot supply a Web Audio meter, the UI says so.
3. Click **Stop recording**. Capture also stops at two minutes, when the tab becomes hidden, when leaving the music route or production, or when the device disconnects. The microphone stream, analysis nodes, timer and capture context are released. Cancelling a pending permission request cancels it within Studio; if the browser later grants the request, its stream is immediately released.
4. Review the local take, name it, or download the original browser recording. Discard removes only the local take. Keep the page open or download it until it is saved; unsaved recordings participate in the page's unsaved-work checks.
5. Click **Save take to library**. The browser decodes its native recording and creates a 48 kHz stereo PCM WAV for the existing authenticated upload/import pipeline. It retains the signed upload and import request key so retries do not repeatedly upload/register the same source. The native recording remains available to download.
6. If processing is still running, click **Check saved take** or refresh recordings. When ready, choose **Place at song beat**, then **Place saved take in song**. This adds an editable audio-take channel. **Save music** persists that placement. Clearing local review keeps the saved library asset.

You can also choose an existing prepared audio asset under **Or use a prepared library recording**. The existing upload/sample-library controls accept recordings made elsewhere. Audio sources must be at most two minutes and downloadable within the existing 25 MB audio-loader limit.

This capture mode records a **standalone take**. It stops song playback and never connects the microphone to speakers. It does not record the synthesizer/mixer output, automatically align an overdub, compensate device latency, or synchronize capture with picture. Those connections remain further production work. Browser permission, actual input hardware and device/browser timing still require the integrated verification sprint.

## Edit the take

Select its channel to edit the song start beat and source in/out points. These are source references; the original library recording is retained. Beat numbering starts at 1 in the interface and 0 in saved source. Moving/trimming a take supports Undo/Redo. Removing its channel removes the song placement, not the library asset.

A take plays at its original pitch and source duration. Tempo edits retain its musical start beat and recalculate its occupied beats from the fixed source duration; there is no automatic time stretching or pitch transposition. The song extends by whole bars when needed, within its existing 128-bar/ten-minute bounds. Invalid edits roll back instead of silently truncating source audio.

Takes pass through their channel filter/delay, gain/pan automation, inserts, group and master. Routing, trim and position changes stop playback for a graph rebuild; fader and mute/solo controls retain the existing live behavior. WAV mixes, processed stems and **Add mix to edit** include the take's audio. Multiple takes use separate channels within the existing sixteen-channel budget.

Song takes are independent of reusable musical patterns. Pattern capture/copy does not turn recorded audio into notes, and local pattern audition excludes song takes. Return to **Song notes · free arrangement** to hear the complete soundtrack. MIDI export omits recorded waveforms; retain the Studio source and saved assets, or export WAV/stems.

## Persistence and limits

Adding an audio take upgrades musical source to **version 5**. Versions 1–4 remain supported. Adding patterns, automation or mixer controls to a version 5 song keeps that version. Older servers reject version 5 rather than silently discarding recordings. Deploy the updated Dashboard/PWA scripts with the server code; no database migration is required.

The source uses `instrument: "recording"`, an authorized ready audio `asset_id`, `sample_in`, `sample_out`, and one fixed-pitch placement in `notes`. Its beat is the musical start; length is `(sample_out - sample_in) * tempo / 60`, with pitch 60 as a source marker. Playback uses Tone.Player rather than repitching the recording through the sampler. Gain/pan, mute/solo, effects and `bus_id` follow the existing channel contract.

Recorded source ranges can span up to 120 seconds and 512 beats, within the song bounds; pitched sample instruments retain their existing thirty-second slice limit and melodic-note bounds. Capture is bounded to two minutes and 25 MB. WAV normalization caps the take at 120 seconds, allowing a small codec/decoder boundary tolerance; longer takes must be downloaded and trimmed. One unsaved local take is retained at a time. It remains bound to the production in which capture began, even if recording finishes after navigation.

The server validates source ownership/site, ready audio status, source range/duration, version and the single fixed-pitch clip. Reusable pattern lanes cannot contain recorded clips. Template-to-episode copies preserve independent take placements while retaining the original immutable audio asset reference. Existing optimistic save locking and production mix handoff remain in use.

Focused checks cover capture cancellation/denial, input measurement, device/timer cleanup and limits using simulated device contracts; native authenticated upload/import retry and UI placement/trim/tempo/undo paths; server persistence/independent copies/access checks; and real PCM decoding/resampling, trim/start/duration/pitch, multi-source playback, mixer routing and live transport. Hardware microphone capture, automated overdub, MIDI performance recording and scoring against synchronized picture remain further work and integrated acceptance.
