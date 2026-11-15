# Lightek AI Studio

AI Studio connects self-hosted generation to the same production library, storyboard and edit used by the rest of Studio. The wider goal remains recurring characters and sets, directed performances, generated media, scoring and delivery from one production.

[CPU procedural scene production](cpu-economy.md) is available through the existing native production workflow without installing diffusion models. Neural generation below is optional and requires a configured neural worker. Only infrastructure operators receive engine/model installation controls.

## Generate and edit

Open a production → **AI Studio**. The application checks the selected local or managed ComfyUI worker, its nodes and installed model names. Only ready recipes can be submitted. Choose a workflow, write the prompt, optionally a negative prompt, and keep or change the seed. The concept-image recipe also offers its installed checkpoint selector.

| Workflow | Inputs and result |
| --- | --- |
| Concept image | Prompt/seed and compatible installed Stable Diffusion checkpoint → 512×512 image |
| Wan 2.2 text-to-video | Prompt/seed → 121 frames at 24 fps, 1280×704 MP4/H.264 |
| Wan 2.2 image-to-video | Ready library still plus prompt/seed → the same video output contract; [input guide](genesis-image-to-video.md) |

Submission creates a durable site/project-scoped asset and queues background work. Image-to-video freezes the prepared source image as an attachment before uploading a canonical PNG to the worker. Jobs retain their original worker identity even if the website’s selection changes. The worker records its engine job ID, polls with scheduled jobs and ingests saved output through normal proxy/thumbnail preparation. Generation history stays attached to the production, including storyboard shot provenance when supplied. **Add result to edit** appends prepared media to the timeline; save the edit to persist placement.

Request keys are idempotent. An uncertain upload/submission is reported instead of automatically creating a duplicate. The browser cannot submit engine URLs, credentials, model paths or arbitrary workflow graphs. Downloads are bounded to 250 MB, output paths are checked and redirects are rejected. No hosted generation API key is used by this path.

## Worker setup

**Genesis worker** installs the pinned ComfyUI engine and verified model packages through the existing Servers/Gatekeeper runtime system. Setup includes ownership, capacity and device checks, resumable model downloads, persisted server phases and private authenticated HTTPS routing. See [Managed Genesis workers](genesis-workers.md) for exact requirements and operating limits. Legacy operator-managed loopback engines remain supported through `STUDIO_AI_URL`.

A worker/model readiness result establishes availability, not generation quality. The video package requires suitable CUDA hardware; a small application VPS is insufficient. No new server is purchased or resized by setup.

## Production scope

| Production need | Current state |
| --- | --- |
| Prompt → image/video → saved asset → edit | Implemented integration; requires the relevant worker/model package |
| Library still → animated video | Implemented image conditioning and frozen-source handoff; actual GPU output review remains pending |
| Consistent recurring character identity | Starting-image conditioning is available; cross-shot identity guarantees and dedicated identity/performance workflows remain outstanding |
| Character speech animation | Offline Rhubarb mouth cues, editable phoneme takes and optional detailed face bindings; [character lip sync](character-lip-sync.md) |
| Editable body animation | Source-bound native Actions/NLA with arrangements and trim/speed/repeat/layer/blend; [body motion](body-motion-clips.md) |
| Neural voice, audio generation and face/performance transfer | Additional eligible models and verified workflows required |
| Editable characters, sets and rendering | Existing native Blender authoring; expanded controls and full production acceptance continue separately |
| Complete animated episode from script to delivery | Not yet accepted end to end |

The Dashboard does not invoke legacy Tripo onboarding for AI Studio; existing Tripo APIs remain for older clients. Generic administrator-owned recipe support for media outputs does not establish that additional speech, music or 3D generation models are installed or accepted.

## Validation

Focused Active Record/Active Storage tests exercise a loopback HTTP engine fixture and actual FFmpeg preparation/ingest. They cover submission/polling, graph binding, input upload, frozen attachments, idempotency, actor/site access, missing models/inputs, generation errors and output-path rejection. DOM fixtures cover prompt and source preservation, selection, pagination, submission, setup and edit handoff. These checks do not perform neural inference or certify model quality.

Final verification must generate representative content on suitable production hardware, review output, and complete the integrated show workflow. Character acceptance must separately verify editable recurring characters, voiced/animated performances, rendered shots and episode assembly. See [Feature sprints](feature-sprints.md).

Engine API reference: https://docs.comfy.org/development/comfyui-server/comms_routes
