# Lightek AI Studio

The target product is a character animation and AI production studio inside Dashboard. A creator should develop recurring characters and sets, direct performances, generate media, edit a show, score it and deliver it from one production. A mesh form, basic toon rig or volume-driven mouth is not fulfillment of that target.

## Implemented in this change

Open a production → **AI Studio**. The application checks an operator-managed local ComfyUI engine, its installed nodes and checkpoint models. Only ready recipes can be submitted. Write a prompt, optionally a negative prompt, choose the installed model and keep or change the seed.

Submission creates a durable, site/project-scoped Studio asset and queues background work. The worker submits the graph, records its engine job ID, polls using scheduled jobs and ingests the saved output through the normal proxy/thumbnail pipeline. Generation history remains attached to the production. **Add result to edit** appends prepared picture or sound to the existing timeline; save the edit to persist its placement.

The default shipped recipe generates a 512×512 concept image from a locally installed compatible Stable Diffusion checkpoint. Installed administrator-controlled recipe graphs can describe image, video, audio or GLB outputs, but this PR does not ship or verify production video, speech or 3D generation recipes. The generic output adapter is not evidence those models are installed or that their generation quality is sufficient.

No hosted generation API key is used by this path. The adapter accepts only a loopback engine, does not accept browser-supplied workflow graphs/URLs or follow output redirects, bounds downloaded media to 250 MB and checks output paths. Request keys are idempotent across interrupted submissions. An uncertain engine submission is reported instead of automatically generating a duplicate. The Dashboard's default Tripo onboarding form is removed; legacy Tripo APIs are retained for existing clients, and are not invoked by AI Studio.

## Installation status and outstanding engineering

This PR does **not** install ComfyUI, download model weights, provision GPU hardware or activate inference on production. The engine must currently exist on the application worker host (default loopback port 8188; `STUDIO_AI_URL` is operator configuration). The UI reports unavailable models/worker and disables generation when they are absent. A loopback adapter does not yet support a separate remote GPU worker.

Dashboard-managed engine/model installation must be connected to server provisioning rather than delegated to customers as manual setup. That includes device/RAM/disk checks, pinned runtime/model releases and licenses, download progress/recovery, private worker connectivity, readiness checks and output verification. No claim that a small web VPS can perform production video inference is made here.

| Production need | Current state |
| --- | --- |
| Local prompt → concept image → saved asset → timeline | Integration implemented; requires an installed engine/checkpoint |
| AI video, dialogue/voice, music generation | Additional tested local recipes/models required; existing music composition remains available |
| Consistent recurring character identity | Reference/version workflow and conditioning required |
| Detailed editable 3D characters, rigging and motion | Existing Blender authoring/character registration is basic; production creation/retargeting still required |
| Phoneme-driven facial animation, singing, lip sync | Existing mouth automation follows volume; phoneme/viseme alignment is not implemented |
| Neural face replacement/performance transfer | Not implemented by this change |
| Complete animated episode from script to delivery | Not yet accepted end to end |

## Validation

Real Active Record/Active Storage tests use a loopback HTTP engine fixture and actual FFmpeg image ingest. They cover submission/polling, graph bindings, idempotency, asset persistence, site/actor access, missing models, generation failure and output path rejection. Browser tests cover prompt preservation, submission and result-to-edit handoff with fixture job responses. Neither test performs neural inference, proves model quality, or constitutes a production generation acceptance test.

The next acceptance gate must generate real content on a managed worker. Character animation acceptance must independently verify an editable recurring character, a voiced and animated performance, a rendered shot and assembly into an episode. Concept images must never be presented as completed rigged characters.

Engine API reference: https://docs.comfy.org/development/comfyui-server/comms_routes
