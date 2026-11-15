# Nevaeh voice and speaking character

Nevaeh can read a response aloud while her 2D character mouth follows the generated audio. The same player serves the shared workspace and the Dashboard assistant dock. The base face remains fixed; only a feathered mouth overlay changes with speech.

## Speak in the workspace or on a Dashboard page

In the shared workspace, enable **Read replies aloud** for spoken answers, or choose **Voice** to start microphone input. Voice input enables spoken replies for that workspace session. In the Dashboard dock, enable **Speak replies** or use **Voice input**. The dock retains the current page/site context when submitting the recognized request.

The browser controls microphone permission and speech-recognition availability. Use HTTPS. Input recognition may use a browser vendor's speech service; this is not an offline recognition guarantee. If recognition is unavailable, type the request. Recognized commands use the same account authority and execution receipts as typed commands.

When a request creates a background action, the spoken queued acknowledgement is followed by a spoken terminal receipt while that request remains active and spoken replies stay enabled. Queued work is not announced as finished. Closing the dock or selecting another request prevents an old result from interrupting you.

Audio playback uses an account-owned playlist of short speech objects. The first encoded AAC item and its timing data become available while later items are still generating. A growing authenticated `.m3u8` EVENT playlist serves the items; HLS.js plays it where Media Source audio is supported, with native HLS as the fallback. Preparing audio is distinct from speaking. Some browsers require another gesture after preparation: **Play reply** starts the ready clip when autoplay is blocked.

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

Voice options retain the basic eSpeak NG U.S. English, British English and Arabic voices. They are explicit alternatives if the natural engine is unavailable; a failed natural request does not silently change Nevaeh's voice. Choose a basic voice and press **Play reply** to retry the text. Neural English voices do not add Arabic neural synthesis. The pace setting is 100–220: **170 means normal** (1.0×) for natural voices; it is an approximate words-per-minute setting for basic voices. Replaying a clip keeps its recorded voice and pace. Changing voice or pace and pressing Play creates a new speech request so the selected voice is actually used.

Model and voice files are pinned by SHA-256 and downloaded at image-build time. See `docker/studio-media/voice/NOTICE.md` for sources, styles and license notices. The Kokoro model weights are Apache-2.0; the Python ONNX wrapper is MIT.

## What the activity label means

The header reports account-owned records: **running** means Studio work is marked running or publication is publishing; **queued** means waiting for a worker. An item queued for more than ten minutes shows **needs attention**, without changing the underlying job to failed or retrying it. **Waiting** identifies planning, approval or payment. Recent successful terminal receipts return to **ready** with a completion message. A submission receipt whose downstream execution is outstanding is not counted as finished. Speech playback temporarily shows speaking/preparing and restores the actual activity message afterward. Opening another page does not start a job.

## Animation accuracy and limits

The current mode is **audio-driven mouth openness**, not phoneme recognition or a full facial rig. Studio's existing audio-envelope decoder measures the actual recording every 40 ms. Short decoding windows preserve timestamps across longer clips despite the media subprocess's stdout budget. The browser selects samples using `audio.currentTime`, so pauses, replay and playback stalls do not use an unrelated animation timer.

A generated speaking-mouth plate is masked onto the existing character around the lips. Hair, eyes, head position and clothing use the unchanged base portrait. It does not synthesize a new face for each response. There are no detailed phoneme-specific lip shapes, eye animation, full-body acting or guaranteed human-quality facial performance in this version. Studio's separate registered-Cast/Rhubarb workflow remains available for phoneme-directed production work.

Spoken text removes fenced code, Markdown link destinations and raw URLs. A response can contain up to 20,000 input characters; a reply reads at most 600 cleaned characters and two minutes of generated audio. Longer responses are explicitly labeled as streaming the first section. Short items are bounded to 120 characters, with at most twelve items, each under twenty seconds. The complete reply is capped at two minutes. The complete written response remains visible. A measured clip over the duration limit fails rather than silently losing the end of its audio.

## Privacy, cancellation and recovery

Speech text, voice settings, WAV and timing belong to the requesting signed-in account. Status/audio/cancellation endpoints recheck ownership. WAV links require the authenticated account; they are not public Active Storage links. Responses use private/no-store caching. Input text goes to the speech process through stdin, not shell evaluation.

Speech clips expire after one day and are inaccessible after expiry. The existing recovery sweep removes expired records and queues attachment purging. Cleanup depends on the existing worker/scheduler being active. Personal memory consent is separate; generating a spoken clip does not opt you into long-term conversational memory.

Submission uses an immutable text/voice snapshot and idempotent request key. Repeating that key with different text/settings is rejected. There are at most three queued/running clips per account and twelve speech submissions per minute. Stopped preparation is not reported as playable success. Interrupted running jobs fail after ten minutes; abandoned queued jobs fail after two minutes. Status polling applies those timeout rules even if the recovery sweep is not running. The player distinguishes waiting for the voice worker from generating speech and shows elapsed seconds. The worker does not automatically regenerate failed clips. Read the response again to make a new attempt after fixing the runtime issue.

## Deployment and verification

Apply migrations `20261115235500_create_nevaeh_speeches` and `20261116001500_create_nevaeh_speech_segments`, restart Rails/Sidekiq workers and retain the minute-based WorkflowSweepJob schedule. Deploy/rebuild the Studio media image: its build now installs the pinned CPU Python dependencies and checksum-verified model/voice files. The source-aware deployment image cache detects this changed context and rebuilds the default image. Custom `STUDIO_MEDIA_WORKER_IMAGE` overrides must be rebuilt by their operator. Deployment performs an offline natural-speech stdin-to-WAV health check under the same worker restrictions; missing models/engines fail this check instead of surfacing first during a conversation. The existing eSpeak NG, FFmpeg, FFprobe and Rhubarb tools remain installed. The segment migration is required for this playlist release.

For local development, install `docker/studio-media/voice/requirements.txt` in a Python 3.12 virtual environment, run `python3 docker/studio-media/voice/install_models.py /your/model-directory`, and set `LIGHTEK_VOICE_PYTHON` to that environment's Python and `LIGHTEK_VOICE_MODELS` to the model directory. These settings apply only outside the production container. Inference never downloads model assets. Natural speech alone gets a 16 MiB executable temporary mount at `/run/lightek-voice` for phonemizer’s per-instance eSpeak shared-library copy; `TMPDIR` points there. The ordinary `/tmp` mount and other media jobs keep their existing restrictions. This is needed for `dlopen`, which cannot map executable library segments from Docker’s default noexec tmpfs. The same configuration is used by the deployment health check and the actual speech worker.

The standalone checks use real speech synthesis, WAV decoding, measured duration, silence/mouth timing, authenticated audio access, foreign-account rejection, cancellation, CSRF and expiry. A 72-second audio fixture verifies that opening silence and late speech keep their original timestamps. Browser checks use actual WAV playback for mouth timing, silence, pause/stop/replay/end, reduced motion, late cancellation, autoplay recovery and Dashboard microphone-to-response wiring with page context.

## Voice queue and playlist objects

`NevaehSpeech` owns ordered `NevaehSpeechSegment` records with their own text, generation status, encoded audio, measured duration and audio-driven mouth timing. Every manifest and item request verifies the requesting account. Segment URLs are private application routes; they never expose public storage links. Already generated audio is retained for replay until the parent expires, and deleting expired speech removes its segment records too. A cancelled/failed playlist closes with ENDLIST; the UI distinguishes this from a finished reply.

The ordinary Sidekiq process starts a `nevaeh_voice` capsule with concurrency one, separate from the default and Studio queues. Dedicated CPU render workers (`STUDIO_CPU_WORKER=1`) do not start this capsule. Speech still needs a running Sidekiq process; a playlist cannot generate speech by itself. There is no new long-lived media server or externally hosted voice API. Stop cancels unfinished generation and stops playlist loading. A new request supersedes the old player's audio and cancels outstanding work.

The deployment must restart Sidekiq to load the capsule. Existing jobs already waiting in `default` are not automatically replayed or migrated. Make a new read-aloud request after deployment. General questions such as “Hello, tell me what you can help me do” now return a permission-aware capability overview before documentation retrieval, so unrelated manuals are not read aloud as the answer.

## Name pronunciation

The written name remains **Nevaeh**. Speech uses the explicit pronunciation **nuh-VAY-uh** (`nəvˈeɪə`) for both natural profiles and phoneme overrides for basic voices. Whole-name matching also handles straight/curly possessives and capitalization; unrelated identifiers such as NevaehSpeech are not rewritten. The override is applied only during synthesis, so stored replies, captions and playlist text retain the correct spelling. Rebuild the changed Studio media image to install the natural-voice rule, and generate a new reply; existing recordings keep their recorded pronunciation.
