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

## Dashboard workspace

The sidebar opens Generate video, Workflows, Media library, Timeline, Character rigs and Export without leaving the production. Generate video keeps the prompt and preview side by side on desktop. Workflows opens the sampling controls, worker setup and performance tools. The inspector displays prompt history, worker activity, available device and VRAM readings, and the same export settings used by Timeline and Export. The worker activity panel shows the application's job phases and failure messages.

Sampler recipes accept 1–60 steps and retain the actual value on the generation receipt. Workflows display their default when the user leaves the slider untouched. CUDA and free VRAM are read from the selected ComfyUI worker when available. A CPU worker or unavailable telemetry is labeled accordingly. Operator system and container logs remain on the host.

### Performance worker setup

**Workflows → Performance tools** can send prepared library media to these operator-configured adapters.

| Engine | Source | Driver |
| --- | --- | --- |
| MuseTalk v1.5 | Portrait or footage | Audio recording |
| LivePortrait | Portrait | Driving performance video |
| FaceFusion | Portrait | Target performance video |

The worker uses the staged media and saves a video into the same generation history and Timeline handoff. Videos and recordings must be 0.1–15 seconds. Use authorized source likenesses and performances.

Run these tools on the [dedicated CPU worker pool](shared-cpu-workers.md). Enable shared Studio storage and the dedicated queue. Set the applicable variables on web and worker processes and install the matching digest-pinned images on every host consuming `studio_cpu` before enabling the tools. One clip uses one CPU host. Adding hosts lets the pool process more clips concurrently.

| Variable | CPU image contract |
| --- | --- |
| `STUDIO_MUSETALK_CPU_IMAGE` | [MuseTalk v1.5](https://github.com/TMElyralab/MuseTalk/tree/0a89dec45a0192b824e3cf4daf96c239440c5ed8) with CPU PyTorch 2.1 or later and matching CPU dependencies. The smoke test used PyTorch 2.1.0, MMCV 2.1.0, MMDetection 3.3.0 and MMPose 1.3.2. Pre-stage v1.5, VAE, Whisper, DWPose, face parsing and face-alignment weights, including the Torch checkpoint cache at `/opt/engine/.cache/torch` or the image's `TORCH_HOME`. The adapter memory-maps the v1.5 UNet checkpoint, uses full precision and runs a batch of one. |
| `STUDIO_LIVEPORTRAIT_CPU_IMAGE` | [LivePortrait](https://github.com/KlingAIResearch/LivePortrait/tree/9b294b3d0536135442ea73cb01e6cb3ca7029dd3) with CPU PyTorch and ONNX Runtime. Install approved weights for the intended use, including the replacement face detector required by upstream for commercial builds. The adapter selects CPU and disables half precision. |
| `STUDIO_FACEFUSION_CPU_IMAGE` | [FaceFusion](https://github.com/facefusion/facefusion/tree/decc6c9d8f8e014878624452c6e8fe208726b4ec) with CPU ONNX Runtime, curl and FFprobe and pre-staged `ghost_2_256`, detector, safety and supporting models with their hash files. Review the model terms for the intended use. The adapter selects the CPU execution provider and bounds ONNX Runtime memory retained between frames. |

Images need Python, FFmpeg with H.264/AAC, and the corresponding engine under `/opt/engine`. The worker uses the locally installed image with networking disabled, a read-only container root, a 12 GiB container memory cap, up to two CPU cores, and a per-job working directory. Budget host memory for the container plus the OS and Sidekiq. It prepares media at up to 1280×720 and 24 fps for video. Studio has no runtime image or weight download.

A performance job can wait up to one hour for a CPU worker and inference is bounded to 30 minutes. Studio surfaces failures in the existing generation history. Before enabling a recipe for creators, run a representative short clip on that pool and confirm its visible performance, audio and Timeline playback. Measure elapsed time and memory on the intended host before advertising throughput. This path uses workers within the installation; the cross-installation render bridge currently accepts procedural movies only. ComfyUI workflows continue to use their selected Genesis runtime.

See [Studio specialist limits and recovery](worker-guardrails.md) for the enforced worker budgets and retry options.
