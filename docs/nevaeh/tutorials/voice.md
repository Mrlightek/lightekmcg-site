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

The default is **Nevaeh · natural** (`nevaeh-natural`), a fixed blend of Kokoro's `af_heart` (70%) and `af_bella` (30%) styles. **Nevaeh · warm** (`nevaeh-warm`) uses the Bella style. The same profile is used on every reply, so her voice identity does not change randomly. This is a synthetic voice design, not a voice cloned from the reference photo.

The CPU-only quantized Kokoro ONNX engine runs inside the existing Studio media container with networking disabled. There is no external TTS API or per-response provider charge. Generation consumes your own CPU and memory. A 5.2-second preview took approximately 14 seconds including process/model startup and 366 MiB peak resident memory in the development workspace; these figures are not production latency guarantees. Long replies take longer. Audio-driven mouth animation and private playback use the same measured WAV contract as before.

Voice options retain the basic eSpeak NG U.S. English, British English and Arabic voices. They are explicit alternatives if the natural engine is unavailable; a failed natural request does not silently change Nevaeh's voice. Choose a basic voice and press **Play reply** to retry the text. Neural English voices do not add Arabic neural synthesis. The pace setting is 100–220: **170 means normal** (1.0×) for natural voices; it is an approximate words-per-minute setting for basic voices. Replaying an existing clip keeps its recorded voice and pace.

Model and voice files are pinned by SHA-256 and downloaded at image-build time. See `docker/studio-media/voice/NOTICE.md` for sources, styles and license notices. The Kokoro model weights are Apache-2.0; the Python ONNX wrapper is MIT.

## What the activity label means

The header reports account-owned records: **running** means Studio work is marked running or publication is publishing; **queued** means waiting for a worker. An item queued for more than ten minutes shows **needs attention**, without changing the underlying job to failed or retrying it. **Waiting** identifies planning, approval or payment. Recent successful terminal receipts return to **ready** with a completion message. A submission receipt whose downstream execution is outstanding is not counted as finished. Speech playback temporarily shows speaking/preparing and restores the actual activity message afterward. Opening another page does not start a job.

## Animation accuracy and limits

The current mode is **audio-driven mouth openness**, not phoneme recognition or a full facial rig. Studio's existing audio-envelope decoder measures the actual recording every 40 ms. Short decoding windows preserve timestamps across longer clips despite the media subprocess's stdout budget. The browser selects samples using `audio.currentTime`, so pauses, replay and playback stalls do not use an unrelated animation timer.

A generated speaking-mouth plate is masked onto the existing character around the lips. Hair, eyes, head position and clothing use the unchanged base portrait. It does not synthesize a new face for each response. There are no detailed phoneme-specific lip shapes, eye animation, full-body acting or guaranteed human-quality facial performance in this version. Studio's separate registered-Cast/Rhubarb workflow remains available for phoneme-directed production work.

Spoken text removes fenced code, Markdown link destinations and raw URLs. A response can contain up to 20,000 input characters; a clip reads at most 1,800 cleaned characters and two minutes of generated audio. Longer responses are explicitly labeled **Speaking the first section**. The complete written response remains visible. A measured clip over the duration limit fails rather than silently losing the end of its audio.

## Privacy, cancellation and recovery

Speech text, voice settings, WAV and timing belong to the requesting signed-in account. Status/audio/cancellation endpoints recheck ownership. WAV links require the authenticated account; they are not public Active Storage links. Responses use private/no-store caching. Input text goes to the speech process through stdin, not shell evaluation.

Speech clips expire after one day and are inaccessible after expiry. The existing recovery sweep removes expired records and queues attachment purging. Cleanup depends on the existing worker/scheduler being active. Personal memory consent is separate; generating a spoken clip does not opt you into long-term conversational memory.

Submission uses an immutable text/voice snapshot and idempotent request key. Repeating that key with different text/settings is rejected. There are at most three queued/running clips per account and twelve speech submissions per minute. Stopped preparation is not reported as playable success. Interrupted running jobs fail after ten minutes; abandoned queued jobs fail after ten minutes. The worker does not automatically regenerate failed clips. Read the response again to make a new attempt after fixing the runtime issue.

## Deployment and verification

Apply migration `20261115235500_create_nevaeh_speeches`, restart Rails/default workers and retain the minute-based WorkflowSweepJob schedule. Deploy/rebuild the Studio media image: its build now installs the pinned CPU Python dependencies and checksum-verified model/voice files. The source-aware deployment image cache detects this changed context and rebuilds the default image. Custom `STUDIO_MEDIA_WORKER_IMAGE` overrides must be rebuilt by their operator. Deployment performs an offline natural-speech stdin-to-WAV health check under the same worker restrictions; missing models/engines fail this check instead of surfacing first during a conversation. The existing eSpeak NG, FFmpeg, FFprobe and Rhubarb tools remain installed. No new database migration is required beyond the original speech migration.

For local development, install `docker/studio-media/voice/requirements.txt` in a Python 3.12 virtual environment, run `python3 docker/studio-media/voice/install_models.py /your/model-directory`, and set `LIGHTEK_VOICE_PYTHON` to that environment's Python and `LIGHTEK_VOICE_MODELS` to the model directory. These settings apply only outside the production container. Inference never downloads model assets. Natural speech alone gets a 16 MiB executable temporary mount at `/run/lightek-voice` for phonemizer’s per-instance eSpeak shared-library copy; `TMPDIR` points there. The ordinary `/tmp` mount and other media jobs keep their existing restrictions. This is needed for `dlopen`, which cannot map executable library segments from Docker’s default noexec tmpfs. The same configuration is used by the deployment health check and the actual speech worker.

The standalone checks use real speech synthesis, WAV decoding, measured duration, silence/mouth timing, authenticated audio access, foreign-account rejection, cancellation, CSRF and expiry. A 72-second audio fixture verifies that opening silence and late speech keep their original timestamps. Browser checks use actual WAV playback for mouth timing, silence, pause/stop/replay/end, reduced motion, late cancellation, autoplay recovery and Dashboard microphone-to-response wiring with page context.
