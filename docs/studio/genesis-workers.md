# Managed Genesis workers

Infrastructure operators open **Dashboard → Studio → AI Studio → Operator neural-worker setup**. Ordinary creators do not receive installation controls and cannot start engine installation. CPU procedural scene production uses the existing deployed Studio runtime and does not need these model packages; see [CPU economy rendering](cpu-economy.md).

For optional neural generation, choose a registered application runtime you can manage, a model package, and CPU or NVIDIA CUDA. **Install engine & models** queues Gatekeeper setup on that server. No new server is purchased or resized by this action.

| Package | Engine/model | Compute | Capacity checks |
| --- | --- | --- | --- |
| Concept images | ComfyUI 0.3.76 + SD1.5 | CPU or CUDA | 8 GiB total RAM, 6 GiB available, 24 GiB free disk; CUDA also needs 4 GiB VRAM |
| Video shots | Same engine + Wan2.2 TI2V 5B, Wan VAE and UMT5 text encoder | CUDA | 32 GiB total RAM, 30 GiB available, 80 GiB free disk and 24 GiB VRAM |

These are installation thresholds, not performance guarantees. Keep headroom for the application and other services; a dedicated worker is preferable. A small application VPS will fail preflight before engine installation. GPU hosts must already have working NVIDIA drivers and the NVIDIA Docker runtime. This installer does not change kernel drivers. Server roles, registration, SSH credentials and ownership use the existing Servers/Gatekeeper system. The selected runtime must belong to the website's account, have an active HTTPS Apache virtual host, and be manageable by the requesting user. Read-only directory access cannot install a worker.

The runtime is built from the ComfyUI commit in `config/studio_ai/packages.json`; Torch is pinned to 2.7.1 and the installed Python dependency inventory is saved inside the image. Each model has a fixed upstream repository revision, expected byte count, SHA-256 and license in that catalog. Downloads resume partial files, verify the full checksum, and replace a model only after verification. No custom ComfyUI nodes or external hosted-generation API nodes are enabled. The Docker base and transitive Python packages are not fully reproducible by digest; update the package catalog and review an engine upgrade as code.

The Dashboard shows persisted queued/running/ready/failed states. While running, it reads server phases and actual model bytes; it does not estimate render percentages. Engine building can take a while before a model download begins. Setup has a two-hour execution bound. A disconnected job is not blindly replayed; after 130 minutes a status check marks an interrupted request failed so an operator can check the worker and retry. Existing verified files and partial downloads are reused. A failed setup does not replace the site's saved worker selection, though a host that fails after container restart may need repair before existing generation can resume.

**Ready** means the authenticated engine answered and downloaded model files passed verification. Individual workflows additionally check `/object_info` for their required nodes and model names. It does not certify generation quality or performance. Generate a sample and review it before production use. This sprint's automated checks cover installation boundaries, downloads, protocol, persistence, authorization, readiness and asset handoff with fixtures. Actual CPU/GPU model inference and representative output review remain part of production verification.

The installed video recipes produce 121-frame, 24 fps, 1280×704 text-to-video or image-to-video shots using core ComfyUI nodes, then save MP4/H.264. **Animate a starting image · Wan 2.2 5B** accepts a prepared library image and uses the same video model package; see [Image-to-video](genesis-image-to-video.md) for input limits, saved sources and handoff. The concept-image recipe uses the installed checkpoint selector. Generated outputs follow **generation → media library → edit** and retain storyboard shot provenance when supplied. These recipes do not create audio, editable rigs or neural face/performance transfer. Offline character speech cues are a separate [implemented workflow](character-lip-sync.md).

Setup pauses new generation for this website and rejects changes while the website has active generation assets. Each new asset saves its original worker identity, so changing the website worker does not reroute older jobs. Legacy local jobs remain on the loopback engine. The browser cannot submit endpoints, credentials, model paths, arbitrary workflow graphs or shell commands.

## Host integration

### Connection diagnosis

Studio preserves the backend connection-check reason and offers **Recheck ComfyUI connection** without clearing the prompt. A disabled Generate button with a failed connection check means no inference request has been submitted. It does not prove that ComfyUI or its models are absent.

The check distinguishes refused connections, timeouts, DNS/TLS failures, HTTP authentication errors, missing API routes, invalid inventory responses, and invalid saved worker configuration. HTTP response bodies, endpoints and credentials are not returned in diagnostics. A reachable engine with an unavailable recipe or incompatible device is reported separately from a connection failure.

Production deployment runs the read-only `script/studio/diagnose_genesis.rb` probe with the application environment. Search deployment logs for `studio_genesis`: the first result checks the local engine; subsequent results check saved worker identities for sites with Studio projects. The probe is bounded to 180 seconds and does not install software, submit prompts, change worker assignments or read out credentials. Incomplete diagnostics are explicitly marked and do not fail the entire platform deployment.

An operator can run the same check from the deployed application directory with its production environment loaded:

```sh
RAILS_ENV=production bin/rails runner script/studio/diagnose_genesis.rb
```

Use the reported error to repair the service, configured endpoint, HTTPS proxy or saved worker credential. Do not replace an existing ComfyUI installation or select an unrelated account's worker as a diagnostic fallback. A successful connection probe is followed by an actual sample generation and output review before declaring neural generation operational.

The container binds only `127.0.0.1:8188`, runs as UID 10001 with a read-only root filesystem, bounded RAM/CPU/logs, and read-only model mounts. Apache proxies `/lightek-ai/` over the worker's existing HTTPS hostname and requires a random Bearer token. The token lives in Vault and root-readable Apache configuration, never in scene manifests or browser responses. One website owns the managed runtime on a host; another website cannot overwrite it. This release manages one Genesis container per host.

Native deployment and fleet update install a root-owned helper plus root-owned catalog. For an existing server managed outside those deployment paths, its administrator can install the same narrowly scoped helper:

```sh
sudo python3 lib/scripts/setup_studio_ai_access.py --app-root /var/www/lightekmcg-site --app-user YOUR_APP_OS_USER
```

The sudo policy permits only the fixed helper under `/usr/local/lib/lightek`, with JSON stdin and a 7200-second timeout. Remote workers reuse Gatekeeper's root SSH transport and receive the trusted catalog from the deployed application. Server access, Vault access, HTTPS reachability and capacity errors are reported as setup failures rather than invented success states.

## Model provenance

- [ComfyUI engine](https://github.com/Comfy-Org/ComfyUI/tree/30c259cac8c08ff8d015f9aff3151cb525c9b702)
- [SD1.5 checkpoint and CreativeML Open RAIL-M license](https://huggingface.co/Comfy-Org/stable-diffusion-1.5/tree/9cfd069101959ca3828bf9c04a4419870832b74f)
- [Wan2.2 weights and Apache 2.0 license](https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/tree/ee6f4a40737a995bf5818954cfce6d59443b0f04)
- [UMT5 encoder bundle](https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/tree/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d)
- [Official Wan2.2 template](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/video_wan2_2_5B_ti2v.json)

See [Studio specialist limits and recovery](worker-guardrails.md) for the enforced worker budgets and retry options.
