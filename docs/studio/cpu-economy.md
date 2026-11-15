# CPU economy rendering and recovery

Lightek can render saved geometry, cameras, lights, materials, rigged performances and animation with Blender’s CPU engine. This path does not download a diffusion model or require NVIDIA/CUDA. It operates on the saved scene and reusable assets; it is not free-form neural text-to-video.

## Choose and render

1. Open a scene’s **Camera & lighting → Render settings**.
2. Choose **CPU economy · up to 512 px / 8 samples** and **Save visual settings**. Requested source dimensions and samples remain editable. The render snapshot proportionally caps the longest edge at 512 pixels, uses even dimensions, caps Cycles samples at 8, and forces Cycles CPU with one rendering thread. Small dimensions have a 16-pixel minimum.
3. Direct/stage the scene with the existing Model, Cast, camera and storyboard tools. Quote/render a still or movie through the existing workflow. Existing payment rules remain in place. The economy profile reduces compute work; it does not automatically change the configured render price or authorize a charge.
4. Open **Renders & handoffs** to see real completed/reused frame counts, worker phases, elapsed execution time and Blender peak resident memory. These are measurements, not invented percentages or promised completion estimates.
5. Add completed output to the edit through the existing artifact handoff. The editable `.blend` retains scene structure, with the resolved economy rendering settings.

New blank productions created through Studio use this profile. Existing scenes and imported/native templates keep their selected/custom settings until explicitly changed. **Custom** retains the existing engine, resolution and sample controls; selecting Cycles there also uses the existing CPU renderer. No existing high-resolution source is silently overwritten.

The reduced economy output may be noisy or too small for a final master. Choose custom CPU settings for higher-quality output and expect additional time/memory. Stateful rigid-body, particle, cloth, fluid, soft-body and dynamic-paint scenes use the existing custom path, or must be baked into ordinary geometry before selecting checkpoint rendering. This change does not implement simulation-cache recovery.

## Saved frames and explicit recovery

Economy movies render frames to an operation-private directory, then encode H.264 MP4 and retain the existing scene soundtrack/character-audio mixing path. Frame ranges remain 1–2400 ordered frames. Rendering uses the existing network-isolated Studio media runtime; no hosted inference service is invoked.

Each completed PNG is atomically committed and journaled with its checksum. The checkpoint fingerprint includes the immutable render manifest, Blender version, engine scripts and resolved input source bytes. Files from a different operation are never reused. If inputs or engine code change, cached frames are invalidated. A corrupt/missing frame is rendered again rather than trusted. Do not modify an operation’s paid snapshot; revised creative work belongs in a new render request.

If a paid economy movie fails or times out, **Resume saved frames · no new checkout** requeues that same authorized operation. Resume verifies project/site access, successful payment, provider/profile/output and failed status. It cannot resume a cancelled render, bypass unpaid checkout or create duplicate queued work. Artifact records are reused on retry. This is explicit recovery, not an unattended retry loop. Economy operations executed by `ExecuteStudioOperationJob` now have expiring worker leases: the sweep or authorized render listing marks interrupted attempts failed for explicit resume. See [Shared CPU workers](shared-cpu-workers.md) for recovery boundaries and other job types.

Valid failed-frame checkpoints remain available on that worker. After a successful operation (or cancellation handled by the render job), temporary frame checkpoints are removed; source/render artifacts and metrics retain their existing storage behavior. Failed checkpoints can still consume disk until resumed or cleaned by an operator. Dedicated workers within one installation can access the same checkpoint directory through operator-configured shared storage. This release does not implement byte-streamed checkpoint transfer between independent installations or a global cache-retention service.

## Worker resource policy

- Economy render containers are limited to 1 GiB RAM and one CPU of scheduling capacity. Cycles rendering and the image-sequence encoder are each configured for one thread; native initialization/helper threads may still exist. This is a container limit, not a claim that the entire Rails/database/Redis host fits in 1 GiB or that any scene will fit that budget.
- One economy render slot is available per application worker host by default. Busy jobs return to pending and requeue after 20 seconds instead of starting another competing renderer. The slot releases when its owning process exits.
- Operators can set `STUDIO_CPU_RENDER_SLOTS` from 1–8 when capacity supports it. `STUDIO_CPU_RENDER_LOCK_ROOT` can coordinate application processes through a shared **local** lock directory with suitable permissions. These local slots do not control unrelated/custom jobs. The separate [shared worker queue and lease layer](shared-cpu-workers.md) can route eligible economy operations to dedicated hosts.
- PNG cache storage is capped at 256 MiB per operation. The worker checks for at least 512 MiB free before rendering another uncached frame. Shorten a shot or free storage if that budget is exhausted.
- Economy final execution is bounded at two hours per attempt; existing draft, performance-preview and source-export time limits still take precedence. Checkpoint recovery can continue completed frame work after a bounded failure. A frame that individually exceeds the limit requires lower complexity or another supported profile.

Infrastructure installation is an operator task. Customer Studio pages do not expose model/engine setup, and the server and install job independently require current super-admin infrastructure authority. Deployment still needs to supply the normal Studio media runtime. The optional neural generation package requirements are separate from procedural CPU production.

## Measurement and evidence

The local reference test rendered a simple procedural cube for 12 frames at 512×288, 8 samples and 24 fps. Its picture-render/encode phase measured **7.246 seconds**, with **235,438,080 bytes (~224.5 MiB)** peak Blender RSS on the implementation environment. This is a half-second toy shot, not a complex-scene or customer-server benchmark. Startup, staging and queue delay are not included in that picture-phase number. Actual job metadata separately records worker execution time; memory is Blender RSS, not a measurement of every container subprocess. The native benchmark ran outside Docker; container resource flags were checked separately. Deployed cgroup enforcement and concurrent production clients remain runtime acceptance.

Focused tests cover resolved profile bounds, preserved source settings, container command limits, slot deferral, payment/site boundaries, single enqueue, real CPU rendering/MP4 probing, corrupt-frame repair, checkpoint reuse, source soundtrack preservation, non-black camera picture, artifact identity and completed-cache cleanup. DOM checks cover profile submission, real frame-progress fields, one resume handoff, and hiding installation controls from creators. Neural-generation protocol/installer and existing production paths remain regression checked.

## Remaining compute work

Dedicated workers within one installation now add tenant concurrency caps and expiring job leases. Authenticated routing between independent client instances and Lightek worker hosts, strict scheduling fairness/compute accounting, transfer without shared storage, economical neural-runtime/model evaluation and representative production-server benchmarks remain separate work. The full production go/no-go stays in the integrated verification sprint.
