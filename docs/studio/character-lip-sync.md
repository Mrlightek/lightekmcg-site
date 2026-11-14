# Speech-driven character performances

Open **Studio → Cast → Direct this take**. Place a character and import a dialogue recording first.

1. Choose the recording and source in/out range. Speech analysis supports 0.1–30 seconds per take.
2. Choose **English speech** or **Phonetic · other languages**. Optionally enter the actual spoken dialogue as a recognition guide.
3. Click **Analyze recording for lip sync**. This queues offline Rhubarb analysis. Queued/running/completed/failed states reflect the saved analysis operation; no estimated progress is shown.
4. Completed analysis switches the draft to **Speech · timed mouth shapes**. Expand the mouth cue editor to review or correct shapes and timing. Times are relative to source-in. Cues must be ordered and non-overlapping; gaps rest the mouth.
5. Save the performance, then preview or quote/export the shot. The existing render workflow includes the recording, expressions, gestures and editable Blender source.

Analysis does not save or overwrite a character performance by itself. Changing the recording, trim or recognition guide while analysis is running discards that result from the current draft and asks for another analysis. Changing the recording or trim after analysis requires a matching new analysis before saving a speech take. Saving retains the analyzed source blob identity. A missing speech engine produces a failed operation, never a successful volume-based substitute. Analyze again to retry a failed request.

| Mouth shape | Intended sound/pose |
| --- | --- |
| A | Closed lips, M/B/P |
| B | Teeth and consonants |
| C | Moderately open, EH |
| D | Wide open, AH |
| E | Rounded, OH |
| F | Puckered, OO |
| G | Lower lip and upper teeth, F/V |
| H | Tongue-raised, L |
| X | Rest |

Rhubarb recognizes speech sounds and maps them to this compact animation vocabulary. It does not provide a word transcript, precise forced phoneme alignment, a voice clone or a photorealistic talking face. English recognition can use the optional dialogue guide; phonetic recognition supports other languages with variable accuracy. Singing can remain in **Volume** mode, which follows loudness. Review recognition against the recording before delivery.

## Character bindings and editable source

New Lightek toon characters contain dedicated `viseme_a` through `viseme_h` and `viseme_x` shape keys. The starter remains a simple toon, with distinct editable mouth silhouettes rather than a detailed facial anatomy model. Imported characters can bind those optional controls when registered in Cast. Every bound control must name a real shape key in the prepared source and use its own key.

For a cue with a dedicated bound shape, Blender keys that shape and suppresses the coarse jaw/wide/round approximation. For an unbound shape, it uses whichever of those three controls the character supplies. Existing jaw-only characters therefore remain usable, with less detail. Saved expression cues can refine individual face controls. Mouth animation is keyed at the scene's frame rate, transitions linearly between frames, and resets at the end of the take.

The cues, source identity, analysis provenance, facial bindings, expressions and gestures stay in the saved scene and immutable render snapshots. The rendered `.blend` contains editable keyframes and packed voice audio. A copied show/episode retains its cues and can refine an unchanged recording independently without rerunning analysis. It does not modify the original episode.

## Runtime and operations

The Studio media image now includes Rhubarb Lip Sync **1.14.0**, downloaded from its official release and verified with SHA-256 `a9a9074862cff47b2d59b8bf399a678a3b0b74f9452ad6ad94cb292913dd8667`. The complete release resources and bundled license information remain in `/opt/rhubarb`. The default image is `lightek/studio-media:20261114`. Normal deployment rebuilds the changed image and probes the speech binary before starting workers. Custom `STUDIO_MEDIA_WORKER_IMAGE` or fallback `STUDIO_ASSET_WORKER_IMAGE` images must include the same executable and resources; the deployment health probe detects a missing binary.

Recognition runs in the existing isolated, network-disabled media container, with one Rhubarb thread, process/resource limits and a writable temporary clip directory. FFmpeg decodes only the selected recording range. No hosted speech or generation API is involved. Development can set `LIGHTEK_RHUBARB` to the official local executable; production uses the fixed container path.

Analysis operations retain the exact audio blob as an attachment and are scoped to the requesting user and scene. They do not change the scene revision. Duplicate request keys return the existing operation; a different payload cannot reuse a key. At most two analyses may be pending/running in a scene. Decoding and recognition have 45/180-second bounds. A durable five-minute watchdog marks an interrupted running operation failed, allowing an explicit new request. Completed work is not resubmitted on duplicate job delivery.

## Focused verification

The sprint checks real offline recognition of a generated spoken test recording, request/source isolation, stale trims, cue validation, failure/retry behavior, saved corrections and independent episode copies. A native Blender check replays those actual cues, verifies dedicated shape-key animation and packed audio in the saved source, and renders two different speech poses. These checks establish the connection; representative human performances, language/rig quality, complete mixed productions and production container deployment remain part of integrated verification.

Upstream: [Rhubarb Lip Sync documentation](https://github.com/DanielSWolf/rhubarb-lip-sync/blob/v1.14.0/README.adoc) · [Pinned release](https://github.com/DanielSWolf/rhubarb-lip-sync/releases/tag/v1.14.0).
