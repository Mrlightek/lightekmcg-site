# Record a microphone overdub with the song

Open **Dashboard → Studio → Music → Record & place audio takes**. Choose **Song notes**, set the song tempo, then choose **Recording range → From song start** and **Overdub bars** (1–16, within the song). Click **Record with song**, allow microphone access and perform against the backing. Permission and recorder preparation finish before playback starts. Use headphones to keep the backing out of the microphone; microphone monitoring through speakers stays silent.

The pass begins at the song start and stops at the selected bar boundary. **Stop recording** keeps a shorter take. Enabling the picture monitor uses the existing music-driven muted picture playback. Pattern audition is not an overdub target.

## Punch selected bars

Choose **Recording range → Punch selected bars**. Set **Punch in · song bar** (starting at 1) and **Punch length · bars** (1–16, bounded by the song end). The displayed range includes its final bar: start 3, length 2 captures bars 3–4 and punches out at the beginning of bar 5. Shortening the song or choosing a later starting bar clamps the shown range before capture.

Click **Record with song**. The backing plays from the song beginning to provide a lead-in. The microphone is active during that lead-in so it is ready, but its samples before punch-in are discarded. The status distinguishes **Song lead-in** from **Recording selected punch range**. Only the chosen range enters the local WAV; there is no padded lead-in. At punch-out, capture and backing stop automatically. Stopping before punch-in creates no silent take; stopping inside the range keeps its shorter audio. If the input attaches late, its actual late position is retained.

Save and place the take using the steps below. Aligned placement targets its original punch bar. Earlier timing correction trims the source as needed at punch-in; later correction delays it and trims as needed at punch-out. Audio never spills outside the selected range through aligned placement. Review the result; correction does not invent missing frames.

Punch adds a separate editable channel. It preserves existing takes and backing notes; use the normal mute, trim and source-position controls to choose what plays together. This is one pass, without loop recording, comp selection, automatic replacement or a metronome count-in. To record another pass, save/download the current one, clear its local review and start again. The microphone is never monitored to speakers.

## Review and place

1. Listen to the local take, rename it or download its original stereo PCM WAV. Nothing uploads automatically.
2. Choose **Save take to library**, then wait for the audio asset to be ready. Upload/import retries reuse the existing signed upload and request key.
3. Set **Shift take earlier · ms** if needed: positive values move earlier, negative values later, from −500 to +500 ms. This is manual timing correction, not automatic device calibration.
4. Choose **Place aligned overdub**. Studio trims audio captured before the backing start and places the remainder at its recorded song position. A punched take is constrained to its selected range. A late-starting input keeps its later position; it is not stretched to hide the gap.
5. Choose **Save music**. The channel's source reference, source trim and note position/length remain editable, with the normal mixer, automation, undo and WAV/stem export paths. The original library recording remains intact.

Aligned placement requires the original recorded tempo. Restore that tempo or use **Place saved take manually** at the chosen song beat. Source placement is bound to the production that recorded the take. Changing the correction after placement does not rewrite an existing channel; edit its start/trim or undo placement and place again.

## Timing and resource handling

The AudioWorklet captures microphone PCM against the same raw audio context used by Tone.js playback. The backing's scheduled start frame and the first captured input frame establish alignment. Punch gates are applied inside the AudioWorklet, including when a bar boundary falls inside a render block. Its start is rounded to the nearest whole audio frame and its duration is rounded down. Recording stops at the selected musical window. This avoids a fractional sample extending the arrangement by an extra bar. Capture timing does not use the browser's UI timer.

Input/output hardware latency, headphones, browser processing and driver behavior still affect physical performance timing. The shared clock establishes a consistent software position; it does not measure microphone or speaker delay. Real device alignment and picture synchronization remain part of integrated acceptance.

Cancel during permission/preparation, Stop, device loss, hidden-page handling and scene navigation release capture-owned nodes and microphone tracks. The shared music audio context remains open. If the audio thread fails to acknowledge Stop within two seconds, the review retains already delivered PCM chunks and shows an error. Input meters measure actual microphone samples.

## Bounds and saved sources

Overdub requires HTTPS, microphone permission and AudioWorklet support. Standalone microphone recording remains available through MediaRecorder where supported. It captures independently of song playback; see [Recording & audio takes](music-recording.md).

The song remains constant-tempo 4/4 at 40–240 BPM. Overdub supports 1–16 bars from the song start or a selected punch-in bar, capped at 120 seconds of captured input. At 40 BPM, sixteen bars take 96 seconds. Capture supports context rates from 8–192 kHz; import normalizes to the existing 48 kHz / 16-bit stereo WAV contract under 25 MB. Punch-in is on whole-bar boundaries within the existing song. There is no count-in, loop recording, comping, playback seeking past the lead-in or automatic latency calibration.

No database migration or new music source version is needed. Audio-take channels use existing version 5 fields; picture scoring starts at version 6. Adding group/master fader automation upgrades to version 7 and insert automation to version 8, retaining recording fields and scoring settings. MIDI exports contain musical notes, not recorded waveform audio. Pending local takes must be saved or downloaded before leaving the page. Capture range controls and local clock alignment live in the current page; after placement and Save music, the ordinary source in/out and song beat reproduce the punch timing on reopening.

## Focused verification

Worklet tests execute the actual processor with PCM fixtures and check exact punch gates inside render blocks, discarded lead-in, silent output, mono/stereo handling, empty/early/late stops, cancellation and shared-context cleanup. Dashboard tests exercise backing/capture, retryable import, tempo guards, correction and source placement. Real Tone.js/offline PCM rendering checks earlier/later alignment, punch placement after saved-source reopening, silence before the target beat and trim. CI also runs a Chromium fake-microphone AudioWorklet test through selected-bar punch recording, WAV review, import and aligned placement. That browser test is not a hardware microphone acceptance test; Chromium could not launch in the implementation container, so its local result is not claimed.

See [Performance recording](music-performance.md) for editable instrument notes, [Picture scoring](music-picture-scoring.md) for picture cues and the [feature checklist](feature-sprints.md) for the final production verification sprint.
