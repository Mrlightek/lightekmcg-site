# Record a microphone overdub with the song

Open **Dashboard → Studio → Music → Record & place audio takes**. Choose **Song notes**, set the song tempo, then choose **Overdub bars** (1–16, within the song). Click **Record with song**, allow microphone access and perform against the backing. Permission and recorder preparation finish before playback starts. Use headphones to keep the backing out of the microphone; microphone monitoring through speakers stays silent.

The pass begins at the song start and stops at the selected bar boundary. **Stop recording** keeps a shorter take. Enabling the picture monitor uses the existing music-driven muted picture playback. Pattern audition is not an overdub target.

## Review and place

1. Listen to the local take, rename it or download its original stereo PCM WAV. Nothing uploads automatically.
2. Choose **Save take to library**, then wait for the audio asset to be ready. Upload/import retries reuse the existing signed upload and request key.
3. Set **Shift take earlier · ms** if needed: positive values move earlier, negative values later, from −500 to +500 ms. This is manual timing correction, not automatic device calibration.
4. Choose **Place aligned overdub**. Studio trims audio captured before the backing start and places the remainder at its recorded song position. A late-starting input keeps its later position; it is not stretched to hide the gap.
5. Choose **Save music**. The channel's source reference, source trim and note position/length remain editable, with the normal mixer, automation, undo and WAV/stem export paths. The original library recording remains intact.

Aligned placement requires the original recorded tempo. Restore that tempo or use **Place saved take manually** at the chosen song beat. Source placement is bound to the production that recorded the take. Changing the correction after placement does not rewrite an existing channel; edit its start/trim or undo placement and place again.

## Timing and resource handling

The AudioWorklet captures microphone PCM against the same raw audio context used by Tone.js playback. The backing's scheduled start frame and the first captured input frame establish alignment. Recording stops at the selected musical window, rounded down to a whole audio frame. This avoids a fractional sample extending the arrangement by an extra bar. Capture timing does not use the browser's UI timer.

Input/output hardware latency, headphones, browser processing and driver behavior still affect physical performance timing. The shared clock establishes a consistent software position; it does not measure microphone or speaker delay. Real device alignment and picture synchronization remain part of integrated acceptance.

Cancel during permission/preparation, Stop, device loss, hidden-page handling and scene navigation release capture-owned nodes and microphone tracks. The shared music audio context remains open. If the audio thread fails to acknowledge Stop within two seconds, the review retains already delivered PCM chunks and shows an error. Input meters measure actual microphone samples.

## Bounds and saved sources

Overdub requires HTTPS, microphone permission and AudioWorklet support. Standalone microphone recording remains available through MediaRecorder where supported. It captures independently of song playback; see [Recording & audio takes](music-recording.md).

The song remains constant-tempo 4/4 at 40–240 BPM. Overdub supports 1–16 bars from the song start, capped at 120 seconds of captured input. At 40 BPM, sixteen bars take 96 seconds. Capture supports context rates from 8–192 kHz; import normalizes to the existing 48 kHz / 16-bit stereo WAV contract under 25 MB. No count-in, loop recording, comping, punch-in, arbitrary record start or automatic latency calibration is included.

No database migration or new music source version is needed. Audio-take channels use existing version 5 fields; picture scoring starts at version 6. Adding group/master automation upgrades to version 7 while retaining recording fields and scoring settings. MIDI exports contain musical notes, not recorded waveform audio. Pending local takes must be saved or downloaded before leaving the page.

## Focused verification

Worklet tests execute the actual processor with PCM fixtures and check frame windows, silent output, mono/stereo handling, cancellation and shared-context cleanup. Dashboard tests exercise backing/capture, retryable import, tempo guards, correction and source placement. Real Tone.js/offline PCM rendering checks earlier/later alignment and trim. CI also runs a Chromium fake-microphone AudioWorklet test through WAV review, import and aligned placement. That browser test is not a hardware microphone acceptance test; Chromium could not launch in the implementation container, so its local result is not claimed.

See [Performance recording](music-performance.md) for editable instrument notes, [Picture scoring](music-picture-scoring.md) for picture cues and the [feature checklist](feature-sprints.md) for the final production verification sprint.
