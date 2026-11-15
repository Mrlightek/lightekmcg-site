# Genesis image-to-video

Animate a prepared library still through the existing self-hosted Wan 2.2 video worker, then use the finished shot in the production edit.

## Create a shot

1. Import a PNG, JPEG or WebP into the production library and wait for preparation to finish. A generated concept image or imported Blender still can also be used once it is a ready library image.
2. Open the production’s **AI Studio**. Set up the **Video shots** Genesis package if needed; see [Genesis workers](genesis-workers.md) for GPU and capacity requirements.
3. Choose **Animate a starting image · Wan 2.2 5B**. Choose a starting image and review its preview. **Load older images** continues the selected website’s eligible library list.
4. Describe the desired scene and motion, optionally adjust the negative prompt and seed, then generate.
5. Review the saved job and **View saved starting image**. When its video is ready, use **Add result to edit**, position/trim it and save the edit.

The recipe uses the existing Wan2.2 TI2V 5B, Wan VAE and UMT5 encoder package. It does not require another model download. Engine readiness checks the installed model names, nodes and the `Wan22ImageToVideoLatent.start_image` input. Missing conditioning support disables the recipe.

## Input and output contract

Starting images must be ready library assets accessible to the requesting actor on the selected website, with a prepared PNG/JPEG/WebP proxy between 1 byte and 10 MB and positive dimensions up to 16,777,216 pixels. The UI filters format/status/size; the server also checks dimensions at submission. Unsupported sources are rejected before a job is created.

Submission attaches the current prepared image blob to the generation and records its source asset, blob and checksum. Replacing the original library image does not change that saved input. Repeating the same request key returns the existing generation; changing the source requires a new generation request. **View saved starting image** uses the generation’s saved attachment and the existing Dashboard site/actor access policy.

Before queue submission, the application media worker decodes the saved source’s first frame into a 1280×704 RGB PNG, proportionally enlarging/reducing and center cropping to fill. It sends that canonical PNG to the selected ComfyUI worker’s authenticated `/upload/image` endpoint. The exact returned input path must be confirmed before it is bound to the server-owned workflow and submitted. The browser sends a library asset ID, never an engine path, arbitrary URL, credentials or workflow graph.

The recipe requests 121 frames at 24 fps and saves MP4/H.264. Output returns through normal bounded download and media ingest, producing the library proxy used by Edit. The application retains the frozen image and prompt/seed/source provenance. Temporary local preparation files are removed; uploaded worker inputs and generated worker files remain in the worker’s existing data directories. This change adds no automatic remote retention cleanup.

The generation shows persisted job phases rather than invented render percentages. An uncertain upload or submission fails visibly and is not blindly replayed; check the worker queue before starting a replacement.

## Scope and verification

Image conditioning supplies a starting frame. It does not guarantee recurring character identity, exact motion or consistency across shots, and does not generate dialogue, audio, lip sync or an editable character rig. Music and [character speech animation](character-lip-sync.md) use their existing production workspaces.

Focused tests use the real database and attachments, real FFmpeg PNG preparation and MP4 ingest, and a loopback ComfyUI protocol fixture. They cover scoped source selection, frozen-image review, original-image replacement, idempotency, multipart upload, workflow binding, missing conditioning support, failed upload confirmation and UI source/pagination/submission behavior. They do not run Wan inference. Actual GPU generation, visual quality, performance and integrated production acceptance remain in the final verification sprint.

The implementation uses the already pinned ComfyUI engine: [Wan conditioning node](https://github.com/Comfy-Org/ComfyUI/blob/30c259cac8c08ff8d015f9aff3151cb525c9b702/comfy_extras/nodes_wan.py) and [image upload route](https://github.com/Comfy-Org/ComfyUI/blob/30c259cac8c08ff8d015f9aff3151cb525c9b702/server.py). It adds an Active Storage attachment, with no new database table or migration.
