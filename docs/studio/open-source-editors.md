# Photo and Video Studio

Studio's basic editing workspaces use locally served miniPaint and Movie Masher. Dashboard supplies identity, website permissions, production records, private storage and exports. No separate editor account, runtime CDN, Node web server or client installation is required.

## Make and save content

1. Open **Dashboard → Studio** and select the website you are working on.
2. Choose **Create artwork** or **Create production**, enter a name and choose landscape, portrait or square.
3. Choose the prominent **Import media** button. Photo imports become editable layers. Video imports become timeline clips. The media-library drawer also offers existing site media.
4. Edit with the editor's tools. Photo provides layers, selections, brushes, text, crop/resize and filters. Video provides its upstream timeline, tracks, player, inspector, titles/shapes and effects. These are the upstream editing interfaces, with Lightek navigation and storage around them.
5. Choose **Save project** or press Ctrl/Cmd+S. Open the production again from Studio to continue. Two tabs cannot silently overwrite the same saved source: a conflicting save offers a project-backup recovery message.
6. Choose **Export PNG** or **Export MP4**. The saved source remains editable. The export appears under **Exports** and in the website's existing media library. Download it or select it in a subsequent production. The existing release/catalog workflows remain available from Studio.

**Download project backup** produces an editable JSON document; **Restore project backup** validates it, saves it under the current production and reopens the editor. Video backups reference their site's original media, so copying the JSON to another account does not grant access to private files.

New campaign productions open Video Studio and retain their campaign brief and return link. Existing productions that use the earlier edit/Blender workspace keep that workspace; no old timeline is discarded or silently converted. Advanced Blender, cast, AI, music and live-room workspaces remain available separately from the basic editor path.

The first release supports sources up to 250 MB per uploaded file, saved project JSON up to 24 MB, photo canvases up to 4096 pixels per side, and video canvases up to 1920 pixels per side with up to 16 tracks/128 clips/10 minutes. Video exports stage up to 1 GB of original source media. The server's HTTP upload limit and available storage also apply. Photo/video editing here uses the client's browser; MP4 export uses the server's isolated CPU media worker. PNG and MP4 exports use the instance's existing resources and introduce no checkout step or external provider fee.

## Deployment

There is no new database migration. Editor sources use an additional ActiveStorage attachment on the existing `StudioScene`; exports use existing `StudioOperation`, `Artifact` and `StudioAsset` records.

The normal native deployment already calls `lib/scripts/setup_studio_media.sh`. This change adds Node and the bundled Movie Masher renderer to the existing media image. Its source-digest check rebuilds the changed image; the setup script verifies `LIGHTEK_MOVIEMASHER_READY=5.1.1` before release. Browser bundles, icons, fonts and notices are committed and served locally. Production exports retain the existing worker container restrictions: no network, read-only root, limited CPU/memory/processes, no capabilities, and only the per-export staging directory mounted.

Instances overriding `STUDIO_ASSET_WORKER_IMAGE` or `STUDIO_MEDIA_WORKER_IMAGE` must deploy an image containing Node and `/opt/lightek-editors/movie-render.cjs`; the default locally built image includes both. Sidekiq must process the existing `studio` queue in `config/sidekiq.yml`. A dead worker cannot be proven healthy by a green browser test: perform the production acceptance below after deployment.

## Upstream and reproducible builds

- miniPaint: `viliusle/miniPaint`, revision `c9192c15918eb61f7dd89e362cf8065a276b89e9` (MIT).
- Movie Masher: version 5.1.1; renderer source revision `d87af5622290fdccedeaad2334b2cd16b0d7cd06` (MPL-2.0).
- React and the upstream browser/editor dependencies are pinned in `vendor/studio-editors/package-lock.json`.
- The browser font is DejaVu Sans; its license and upstream/component notices ship beside the bundles and are linked from the editor.

To rebuild on a development/CI Linux host with Git, Node, npm and DejaVu Sans installed:

```sh
npm ci --prefix vendor/studio-editors --ignore-scripts
node script/studio/build_open_source_editors.mjs
```

The build retrieves the exact upstream revisions, verifies them, builds the client and isolated renderer, and records asset digests in `public/lightek/editors/manifest.json`. Lightek's bridge sources are in `app/javascript/studio_editors`, `public/lightek/studio-editors.js` and `lib/studio_editors/render.ts`. Core editing controls are reused from upstream. miniPaint's local startup integration scopes its settings, preserves the selected canvas dimensions and delegates leave/save handling to Dashboard.

## Acceptance and Monday launch gate

`test/standalone/studio_editors_checks.rb` exercises real models, storage, controllers, CSRF, site isolation, source validation, committed save revisions, queue submission recovery and the Movie Masher/FFmpeg renderer. `test/javascript/studio_open_source_editors_test.cjs` runs the real upstream interfaces against those real Rails controllers and ActiveStorage blob/disk routes through a test transport. Only private host authentication is supplied by the fixture; editor APIs and render responses are not canned.

The browser test creates a layered photo and an edited video, saves/reopens them, exports and downloads PNG/MP4, verifies the MP4's video/audio streams, and checks the player/timeline/inspector layout at 1440/1024/390 widths. Separate advanced Blender/AI tests still have their own engine requirements.

Before treating this as ready for Monday's launch, repeat on the deployed site under a normal client account:

- Create artwork, import a real image, change a layer, save, close/reopen, export and download PNG.
- Create a video, import a real supported clip with sound, change the edit, save, close/reopen, export and play the downloaded MP4 with sound.
- Confirm both exports appear in that account's media library and another account cannot open the projects or sources.
- Confirm exports leave `pending`/`running`, and the worker/image readiness checks pass on that server.

This release closes the basic photo/video editing path. It is not evidence that neural generation, character performance, unrestricted third-party effects, a complete Resolve workflow or external social publishing have passed production acceptance.
