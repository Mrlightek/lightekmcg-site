# Lightek AI Studio

AI Studio connects self-hosted generation to the same production library, storyboard and edit used by the rest of Studio. The wider goal remains recurring characters and sets, directed performances, generated media, scoring and delivery from one production.

[CPU procedural scene production](cpu-economy.md) is available through the existing native production workflow without installing diffusion models. Neural generation below is optional and requires a configured neural worker. Only infrastructure operators receive engine/model installation controls.

## Native 2D scenes and parallax

Studio Create opens **2D Scene & Parallax** in Dashboard and PWA. It checks the native media runtime independently of Genesis. A missing ComfyUI connection does not disable this tool. This path does not install or invoke ComfyUI, Torch, neural weights or Blender.

Enter **A nighttime park with a character sitting on a bench**, then generate a layout or render a preview. The bounded prompt parser supports daytime/nighttime parks, optional tree/bench counts, a seated character illustration and left/right camera movement. Omitted counts use seeded defaults (3–5 trees and 1–2 benches), with placement around the path and scene edges. Unsupported prompts return an example. This is procedural template composition, not a trained neural model or arbitrary prompt-to-video inference.

Six starter illustrations provide day/night skies, ground/path, an oak tree, a bench and a seated person. These are basic reusable artwork, not a rigged character system. Prepared library images can also become layers. Edit positions, sizes, fit, opacity, rotation and depth. Nested groups carry transforms, stacking contexts and inherited depth. Scene saves use optimistic locking and preserve other scene settings.

**Z-index controls drawing order. Depth independently controls camera displacement**, so foreground assets move farther. The editor preview and renderer use the same clip clock. Pause or scrub Preview position to inspect a frame; the preview repeats the clip while export plays it once.

Select any asset or nested group and apply **Sway**, **Float**, **Drift left** or **Drift right**. Motion consists of 2–12 linear position keyframes, expressed as X/Y offsets in the parent's coordinates. Edit offsets and keyframe times, set a 0.25–10 second duration, and choose looping or one-shot playback. Loop endpoints stay identical. A group's motion moves all its children; child motion adds to inherited group movement. Static parent rotation and scale also transform a child's motion. Layer order and parallax depth stay independent from these tracks.

Append **and a gentle breeze** to a supported park prompt to give its trees seeded sway tracks. For example: **A nighttime park with a character sitting on a bench and a gentle breeze**. Tree movement is translation of the existing illustrations, not mesh deformation or physical wind simulation.

Animation tracks are saved with the composition and frozen into queued renders and full-export quotes. A two-second preview retains the full track duration and original clip timing; it does not compress a longer animation into two seconds. Changing output size scales normalized offsets with the canvas. These tracks do not rescale assets or animate their rotation/opacity. Walking cycles, speaking, rigging, physics and arbitrary character performances remain future work for this compositor.

| Limit | Native compositor |
| --- | --- |
| Editable graph | 48 nodes, 24 image layers, four nesting levels, 64 KiB JSON; 2–12 keyframes per node, ±30% offsets |
| Source images | Owned/site-scoped PNG/JPEG/WebP/GIF/AVIF; 25 MiB each, 64 MiB combined |
| Private preview | At most 640 pixels on the long edge, two seconds, 12 fps |
| Full export | Up to ten seconds, 24 fps; even dimensions, maximum 1920×1080 pixels in area |
| Raster budget | Rotated layer edge at most 4096 pixels; total area at most six canvases |
| Worker process | Existing media image, 512 MiB container cap, CPU slot, 180-second timeout |

Library images require raster signatures. Trusted template SVG bytes and source blobs are frozen onto each operation before queuing. Later scene edits cannot change a queued render. The renderer uses fixed local filenames without networking. The deployed media image needs Python 3, FFmpeg with SVG decoding/H.264 encoding, and ImageMagick. Readiness rasterizes a tiny SVG and processes the result; it checks the local runtime, not whether a separate worker consumes its queue. Creator requests never pull a runtime image.

Rendering uses `ExecuteStudioOperationJob`, existing leases/cancellation, CPU concurrency controls and shared storage. It uses the local Studio queue or configured dedicated CPU queue. The cross-installation Blender federation protocol does not accept this composition format. The 512 MiB cap is a bound, not a guarantee every scene fits or that a busy 2 GB host has sufficient headroom. Measure representative exports on the deployment host.

Preview artifacts cannot enter reusable assets or publishing. **Get 2D export price** creates an immutable full-render snapshot and uses existing Dymond Bank quote/checkout, credentials and canonical signed callback. Only paid final operations execute. Completed full clips can enter the Media Library/Timeline handoff. No new payment credentials or callback are introduced.

### Capability and MCP contracts

Authenticated capabilities are `workflow.status`, `workflow.plan`, `workflow.save`, `workflow.create` and `workflow.quote` under the existing Studio workspace and PWA bridge. Creation accepts a scene ID, normalized composition (or supported prompt/seed) and idempotent request key. Saving requires the scene lock version. Actor, site, project and source ownership are rechecked on execution.

Optional `POST /api/lightek/pwa/studio/workflows/:id/mcp` supports MCP initialization and job-scoped `studio_render`/`studio_result`. A signed one-hour token selects one existing job; callers cannot supply commands, files or other scenes. The browser does not require MCP to render. The native queue owns execution and operation/artifact identities.

### Validation and production acceptance

`test/standalone/studio_native_workflow_checks.rb` exercises real Active Record/Active Storage submission, snapshots, save conflicts, tenant boundaries, idempotency, MCP scoping, unpaid rejection and native H.264 rendering. ComfyUI and Blender constructors fail the test if invoked. `test/operations/studio_layered_renderer_test.py` measures exported pixels to verify foreground movement exceeds background movement. DOM checks cover layout, layer/group motion controls, deterministic preview scrubbing, saving and rendering while rejecting Genesis status calls. Encoded-pixel tests also verify loop return positions and one-shot asset displacement with a stationary camera.

After deployment, submit a preview from the actual PWA, reopen saved layers, complete an authorized final checkout, inspect the full video, add it to Timeline and verify publishing. Local fixtures do not establish a real payment, production queue consumption, host memory headroom or completed episode production.

## Generate and edit

For optional neural tools, open a production → **AI Studio** and select Wan or Concept Art. The application checks the selected local or managed ComfyUI worker, its nodes and installed model names. Only ready recipes can be submitted. Choose a workflow, write the prompt, optionally a negative prompt, and keep or change the seed. The concept-image recipe also offers its installed checkpoint selector.

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
