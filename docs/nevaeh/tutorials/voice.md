# Nevaeh voice and speaking character

Nevaeh can read a response aloud while her 2D character mouth follows the generated audio. The same player serves the shared workspace and the Dashboard assistant dock. The base face remains fixed; only a feathered mouth overlay changes with speech.

## Speak in the workspace or on a Dashboard page

In the shared workspace, enable **Read replies aloud** for spoken answers, or choose **Voice** to start microphone input. Voice input enables spoken replies for that workspace session. In the Dashboard dock, enable **Speak replies** or use **Voice input**. The dock retains the current page/site context when submitting the recognized request.

The browser controls microphone permission and speech-recognition availability. Use HTTPS. Input recognition may use a browser vendor's speech service; this is not an offline recognition guarantee. If recognition is unavailable, type the request. Recognized commands use the same account authority and execution receipts as typed commands.

When a request creates a background action, the spoken queued acknowledgement is followed by a spoken terminal receipt while that request remains active and spoken replies stay enabled. Queued work is not announced as finished. Closing the dock or selecting another request prevents an old result from interrupting you.

Audio playback waits for an actual generated WAV and its timing data. Preparing audio is distinct from speaking. Some browsers require another gesture after preparation: **Play reply** starts the ready clip when autoplay is blocked.

## Playback controls

- **Pause voice** pauses the media clock and closes the mouth. Play resumes from that position.
- **Stop voice** stops playback immediately and resets the clock; it also requests cancellation of queued/running clip preparation. A finished clip remains replayable during its private lifetime.
- **Replay reply** replays the loaded clip without generating a second recording.
- The mouth closes on silence, waiting, pause, stop, error and the actual end of playback. Reduced-motion preferences suppress mouth motion while retaining audio and accessible status.
- Escape stops listening and speech in the shared workspace. Closing the dock stops its microphone and speech; stopping speech does not undo business tasks already submitted through voice input.

Each window has one audio player. Multiple visible portraits mirror that player rather than playing duplicate audio. A newer reply replaces the previous one. A stopped or superseded preparation cannot begin playback when its network response arrives late.

## Current voice and options

Version one uses the existing local eSpeak NG synthesizer with a female stock voice. Its default is **U.S. English female** (`en-us+f3`) at **170 words per minute**. Voice options also expose British English female and Arabic female presets, plus a 100–220 words-per-minute setting for the next response. Replaying an existing clip keeps the voice that produced it.

This is a synthetic stock voice and can sound robotic. The supplied appearance reference does not provide or clone a person's voice. The audio generation path is separate from the playback and mouth renderer so a future neural speech model can supply the same private audio/timing contract.

A next quality candidate is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), an open-weight speech model whose model card lists Apache-2.0 weights and production use. It is not installed or selected by this release. The next voice pass should audition appropriate voices, measure CPU latency/memory on the deployed worker, pin the chosen model/voice files and approve Nevaeh's voice profile before changing the default.

## Animation accuracy and limits

The current mode is **audio-driven mouth openness**, not phoneme recognition or a full facial rig. Studio's existing audio-envelope decoder measures the actual recording every 40 ms. Short decoding windows preserve timestamps across longer clips despite the media subprocess's stdout budget. The browser selects samples using `audio.currentTime`, so pauses, replay and playback stalls do not use an unrelated animation timer.

A generated speaking-mouth plate is masked onto the existing character around the lips. Hair, eyes, head position and clothing use the unchanged base portrait. It does not synthesize a new face for each response. There are no detailed phoneme-specific lip shapes, eye animation, full-body acting or guaranteed human-quality facial performance in this version. Studio's separate registered-Cast/Rhubarb workflow remains available for phoneme-directed production work.

Spoken text removes fenced code, Markdown link destinations and raw URLs. A response can contain up to 20,000 input characters; a clip reads at most 1,800 cleaned characters and two minutes of generated audio. Longer responses are explicitly labeled **Speaking the first section**. The complete written response remains visible. A measured clip over the duration limit fails rather than silently losing the end of its audio.

## Privacy, cancellation and recovery

Speech text, voice settings, WAV and timing belong to the requesting signed-in account. Status/audio/cancellation endpoints recheck ownership. WAV links require the authenticated account; they are not public Active Storage links. Responses use private/no-store caching. Input text goes to the speech process through stdin, not shell evaluation.

Speech clips expire after one day and are inaccessible after expiry. The existing recovery sweep removes expired records and queues attachment purging. Cleanup depends on the existing worker/scheduler being active. Personal memory consent is separate; generating a spoken clip does not opt you into long-term conversational memory.

Submission uses an immutable text/voice snapshot and idempotent request key. Repeating that key with different text/settings is rejected. There are at most three queued/running clips per account and twelve speech submissions per minute. Stopped preparation is not reported as playable success. Interrupted running jobs fail after five minutes; abandoned queued jobs fail after ten minutes. The worker does not automatically regenerate failed clips. Read the response again to make a new attempt after fixing the runtime issue.

## Deployment and verification

Apply migration `20261115235500_create_nevaeh_speeches`, restart Rails/default workers and retain the minute-based WorkflowSweepJob schedule. The existing Studio media runtime must include eSpeak NG, FFmpeg and FFprobe. Production uses its existing isolated media container; a new external speech service or GPU is not required for this version.

The standalone checks use real speech synthesis, WAV decoding, measured duration, silence/mouth timing, authenticated audio access, foreign-account rejection, cancellation, CSRF and expiry. A 72-second audio fixture verifies that opening silence and late speech keep their original timestamps. Browser checks use actual WAV playback for mouth timing, silence, pause/stop/replay/end, reduced motion, late cancellation, autoplay recovery and Dashboard microphone-to-response wiring with page context.
