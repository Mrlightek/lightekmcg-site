# Distributing PhotoCraft Web for Studio

The fork branch `lightek/export-bridge` starts at upstream `v0.23.1` (`45066c48292e92229ada3459a83453439514c83d`). Its only engine divergence is the export bridge in `apps/photocraft-web/src/web.rs`, including its wasm-bindgen import and access to the running web app. PhotoCraft's file menu and browser download implementation remain unchanged.

## Browser contract

`window.photocraftBridge` exposes `version: 1` and `exportBytes(format?: "pcraft" | "png"): Promise<Uint8Array>`. The default is native `pcraft`. Export uses `photocraft_io::export`; the native path calls `photocraft_format::save_to_bytes` with the document and its previews. The native manifest carries the live selection. PNG is a flat option. The bridge rejects unsupported formats and a blank editor. It neither saves nor downloads the open document and leaves the path, dirty state, and undo history intact.

Studio calls `exportBytes("pcraft")` inside the configured PhotoCraft iframe after Run is clicked. This keeps access to the editor's API on the editor's origin. The existing MessageChannel transfers the snapshot to the Rails parent relay, which submits it to the existing apply endpoint. Studio reads the context from that exact snapshot. The file input remains visible. A selected file takes precedence, and stock builds or unknown bridge versions use the file input. The result is still a downloadable PNG.

## Build, publish, and sync

Use the upstream toolchain and install the `wasm32-unknown-unknown` target. Use upstream's pinned Trunk version for the base tag. From the fork root, `packaging/web/package.sh` runs the release builds for both the application and boot module and produces the static ZIP. Publish its contents to the dedicated PhotoCraft editor origin with the Studio script and configured parent origin. Set `STUDIO_PHOTOCRAFT_EDITOR_URL` to that versioned build after checking the bridge against the packaged site. Preserve the stock deployment for rollback and retain the upstream license and attribution files.

The pinned packaging script copies the application's JS glue but omits the relative imports that Trunk emits in `dist/web/snippets`. Include that directory under `app/` in the ZIP. This is an assembly step and leaves the fork's source at one changed file.

```sh
export CRAFT_I18N_DIR=/path/to/pinned/craft-i18n
export CRAFT_I18N_REQUIRED=1
export PHOTOCRAFT_VERSION=0.23.1-lightek.1
packaging/web/package.sh
bundle=photocraft-web-$PHOTOCRAFT_VERSION
mkdir -p "target/web-package/$bundle/app/snippets"
cp -a dist/web/snippets/. "target/web-package/$bundle/app/snippets/"
(cd target/web-package && zip -q -r "../../dist/release/$bundle.zip" "$bundle/app/snippets")
```

Check upstream stable releases weekly and sync security fixes promptly. Around the pinned release, stable tags sometimes arrived every few days. Sync at least weekly when stable updates are available. Rebase the one-file bridge on the chosen stable tag and rerun the browser checks before distribution. The small change surface should make most syncs routine. Changes to eframe's web runner or the document serializer still warrant review.


For cross-origin acceptance, start the existing PostgreSQL Studio browser fixture with `STUDIO_PHOTOCRAFT_BRIDGE_TEST=1` and the PhotoCraft editor URL pointed at the test host's `/photocraft/` path. Run `node test/browser/studio_photocraft_export_bridge.mjs` with `PHOTOCRAFT_WEB_ROOT` set to the extracted release. The test uses Chromium, FFmpeg and the existing PhotoCraft CLI adapter. It compares applied pixels with and without the selection and exercises the native Save As download and the manual fallback. The pinned web build disables Save a Copy for the proof document. Its native Save As handler remains available.
