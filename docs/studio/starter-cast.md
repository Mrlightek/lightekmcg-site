# Start with Rain and Snow

Open **Dashboard → Studio & broadcasting → Media Studio**. On the production home screen, optionally enter a project name and choose **Use Rain & Snow**. Lightek downloads the official Blender Studio characters, checks their pinned SHA-256 hashes, prepares native sources, and builds a two-character project with a camera, lights, floor and editable head gestures. Progress stays on the card. **Open character scene** opens the prepared scene; failed attempts expose **Retry starter scene**. Reloading the workspace retrieves the latest request for this account and application.

The first download can take several minutes. Sources are cached for the same account and application. Repeated submissions of the same request reuse its job and project. The job runs on the existing `studio` queue; it does not install an external generation service or require an API key.

These are the real Rain v3 and Snow v4 meshes and rigs, rather than generated approximations. The native `.blend` keeps armatures, drivers, constraints, materials and packed textures. The browser GLB is a static proxy; it does not replace the native source. **Model & animate** exposes the existing native authoring controls. The starter's head keys are a small editable example, not a finished acting performance. Automated dialogue, rig retargeting, phoneme lip sync, likeness generation and voice generation are not supplied by this starter.

Source pages and required credits:

| Character | Source | Credit |
| --- | --- | --- |
| Rain | [Rain v3](https://studio.blender.org/characters/rain/v3/) | Rain Rig (CC) Blender Foundation · studio.blender.org |
| Snow | [Snow v4](https://studio.blender.org/characters/snow/v4/) | Snow Rig (CC) Blender Foundation · studio.blender.org |

Both sources use [CC-BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit metadata stays with the source assets and generated scene; the `.blend` also contains a Source credits text block.

## Deployment

Deploy the application, run migrations (including `20261112040000_register_studio_starter_cast`), and restart Rails and the Studio queue. Normal deployment uses the updated setup scripts to build `lightek/studio-media:20261112` and, when enabled, `lightek/studio-workstation:20261112`. Both pin the checksum-verified official Blender **4.5.16 LTS** runtime. These current character archives contain Blender 4.4 data and cannot be prepared with the old 4.0.2 worker. Custom worker-image overrides must also be upgraded. The job reports an actionable version error on an older worker.

No character ZIP or Blender executable is checked into the application repository. Allow outbound HTTPS to the pinned official Blender hosts for first installation/import. Subsequent Blender processing keeps the existing isolated, network-disabled worker policy. Downloads, extraction and native processing use disk-backed `storage/studio-tmp` job directories, removed when each operation exits, rather than placing large character files in a memory-backed `/tmp`. Keep sufficient free storage for the worker image, source archives, packed native files and previews.

## Verification

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile STUDIO_STARTER_LIVE_DOWNLOAD=1 BLENDER_BIN=/path/to/blender bundle exec ruby test/standalone/studio_starter_cast_checks.rb --name /test_starter_cast_/
STUDIO_CHROMIUM_EXECUTABLE=/path/to/chromium node test/javascript/studio_dashboard_browser_test.cjs
```

The real-source test downloads and imports both archives, creates the native project, reopens the packed source after temporary import files are removed, checks both armatures and retained drivers, checks moving head controls, and renders a two-second H.264 movie through the application provider. The browser test uses API fixtures to exercise queue/progress/open controls alongside typing and media-import regressions at 1440, 1024 and 390 pixels. This does not establish production-server performance, full cinematic production quality, or neural generation. The Docker image build and production deployment require their own acceptance.
