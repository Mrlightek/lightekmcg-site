# Studio Macro Maker runs

Open a published composition or a built-in operation from `/studio/macro_maker`. The run form uses the latest published version for the selected surface. Run history shows the signed-in user's ten most recent executions of that operation. Run status and downloads require the same site and user as the run.

The GET and POST share `/studio/macro_maker/compositions/:operation_id/run?surface=image`. A multipart POST accepts a PhotoCraft upload in `input_file`, public parameters as a JSON object in `parameters`, and other public inputs as a JSON object in `inputs`. Before creating a run, the server validates the public bindings and checks command requirements against the Macro Maker's empty live context. Invalid parameters and uploads create no run record.

PhotoCraft accepts PNG, JPEG and WebP input up to 20 MiB and exports PNG synchronously, with a nine-second engine session budget. EffectCraft starts a fresh project in a background job. The job pins the published operation version selected when the request was accepted.

## EffectCraft export

EffectCraft 0.25.1 documents the following CLI syntax in its help. The job saves the recipe's editable project through the MCP recipe session first, then runs this command with absolute paths.

```sh
effectcraft-cli render /absolute/project.ecproj --out /absolute/output.mp4 --format h264 --progress
```

The CLI renders the saved active composition. It accepts an optional `--comp` with a composition ID or name for explicit selection. The CLI handles the render queue internally. It switches any existing queue entries off with `renderQueue.setRender`, calls `renderQueue.add` for the selected composition with the output path, H.264 format and full composition time span, and starts it with `renderQueue.render` using `{"wait":false}` while the CLI monitors completion. Those command IDs are listed by `effectcraft-cli commands --filter renderQueue --json`.

The MCP recipe session does not provide render progress. The render subprocess emits `progress <frames done> <total> <seconds elapsed> <seconds left|->` on piped stderr when available. Turbo Streams displays a percentage only from reported frame counts. A short render may show only the rendering state and the final result. The authorized status endpoint lets the browser recover the result if a broadcast arrives before its subscription connects.

The motion job uses a shared 600-second engine deadline for recipe execution and video export. Set `STUDIO_EFFECTCRAFT_RENDER_TIMEOUT_SECONDS` to a positive number on the Sidekiq worker to tune the budget. It also needs `STUDIO_EFFECTCRAFT_CLI` and the application's Active Storage and Action Cable connections. A 15-second, 1080p test composition with 360 frames rendered in 4.4 seconds in this checkout. That is a proof-scale measurement. Production render time depends on resolution, frame count, effects and worker capacity.

Active Storage holds the MP4 as the primary output and the editable `.ecproj` as the source project. If rendering fails or times out after the project is saved, the run is marked failed with a render-phase StepError, and the editable project remains downloadable with `?file=project`. Recipe-phase failures are recorded separately. The engine process group is stopped on timeout, and the private work directory is removed after the job exits.

A JSON client gets HTTP 202 with a scoped status URL for a queued motion run. The status response includes download URLs once available and a structured error on failure. The Turbo client receives an initial stream with a run-specific subscription, followed by the result and history updates.

Macro Maker still requires a fresh EffectCraft project and renders its active composition. Features that depend on live document or timeline context remain blocked in this surface.

## Acceptance

Use the PostgreSQL browser fixture described in `docs/studio_macro_maker_editor.md`, then run `node test/browser/studio_macro_maker_run.mjs` while the fixture is running. The check uses `ffprobe` to verify the H.264 stream and EffectCraft to reopen the attached project. It also exercises the job broadcast, scoped status and downloads, PhotoCraft byte parity, video render failure and timeout recovery, and temporary-directory cleanup.
