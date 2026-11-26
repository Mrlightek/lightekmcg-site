# Studio Features in the editors

Macro Maker links to the configured PhotoCraft and EffectCraft iframe hosts. Set `STUDIO_PHOTOCRAFT_EDITOR_URL` and `STUDIO_EFFECTCRAFT_EDITOR_URL` to HTTPS URLs you control, on dedicated origins separate from the Rails app and outside the session cookie's domain. Serve the corresponding engine web release on each host. Use the release's normal WASM/JavaScript content types and allow embedding by the Rails origin. In each engine's page, install the bridge for that specific engine and Rails origin.

Copy `app/javascript/studio_editor/features.js` and `app/javascript/macro_maker/form_values.js`, preserving the relative directories. Add the following to the editor page, with the actual Rails origin and the applicable engine name.

```html
<script type="module">
  import { installStudioFeatures } from "./studio_editor/features.js"
  installStudioFeatures({ parentOrigin: "https://studio.example.com", engine: "effectcraft" })
</script>
```

The Rails page transfers one MessageChannel port to the configured iframe origin. The child checks the sender window and the exact permitted origin before accepting it. The parent relays catalog requests, uploads, run status, and downloads on that port. It uses its own same-origin session and CSRF token. The child receives neither cookies nor tokens and cannot tell the parent to fetch an arbitrary URL. The apply endpoint enforces Studio site membership and published operation visibility. Run status and downloads are owned by the original site and user.

Apply accepts multipart `input_file`, `editor`, `context`, `parameters` and `inputs` at `POST /studio/macro_maker/compositions/:operation_id/apply`. Context, parameters, and inputs are JSON objects. The server requires literal boolean values for known context flags. It returns 422 with structured errors and missing flag names when applicable. Context flags describe editor state and are used for applicability. They do not authorize the request or convert application state into recipe parameter values.

## PhotoCraft 0.23.1

Studio uses the current document automatically when the editor exposes the v1 export bridge. The bridge returns native `.pcraft` bytes, and Studio checks the selection in that snapshot before applying the feature. With a stock build or an unsupported bridge version, choose a saved native snapshot or an exported image in Studio Features. You can also choose a file to override automatic export.

A native `.pcraft` snapshot carries the selection mask. Flat PNG, JPEG, and WebP uploads carry pixels. The panel reads the snapshot manifest and leaves flags it cannot establish, such as selected layer, unset. Download the PNG result and open it as a separate document in PhotoCraft.

See [distributing a PhotoCraft web build](studio_photocraft_distribution.md) for the pinned fork and bridge contract.

## EffectCraft 0.25.1

Studio Features reads `effectcraft.inspect()` for the active composition, selected layers, and playhead. It calls `effectcraft.execute("file.saveCopy", {path})` and reads the bytes with `effectcraft.readFile(path)`. The original project stays intact, and the browser release also downloads the saved copy. A 202 response starts status tracking. The panel shows the reported render percentage when available. The editable result opens with `effectcraft.addFile(file)`; the panel can also reopen the captured original snapshot. MP4 is available as a download. The browser sends referenced footage, proxy files, and image sequence frames available in its file table. The server checks every reference before creating a run, including inactive proxies. Missing references return HTTP 422 with `kind: "missing_assets"` and an exact `missing_assets` list. Embedded data footage travels in the project JSON. Supplied files use multipart `assets[]` with corresponding original path strings in the JSON `asset_paths` array. Limits are 120 assets, 100 MiB of media, and a 20 MiB project. 3D model dependencies are outside this transfer.

The render worker stages media under its run directory and relinks the render copy. The editable output restores the original editor paths, so it can reopen against the editor's existing media. A standalone download still needs those source files. Staged uploads are purged after the run.

The operation always runs against the export. Canvas insertion and command-level, in-place execution are outside this integration. UI-only state that the exported file does not retain is unavailable in the headless engine. The macro can accept explicit parameters for values it needs from the editor.

## Acceptance

Start the PostgreSQL Macro Maker browser fixture. Configure the editor URL variables to the test host's PhotoCraft and EffectCraft paths and run `node test/browser/studio_editor_apply.mjs` with `PHOTOCRAFT_WEB_ROOT` and `EFFECTCRAFT_WEB_ROOT` set to the unpacked engine releases. The test host installs the bridge for the fixture's parent origin.
