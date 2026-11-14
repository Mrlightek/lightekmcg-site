# Shots & Storyboard

Open a native Studio production and choose **Shots**. The board uses the same scene, cast, cameras, performances and render queue as Stage & FX, Animation and Deliver.

## Build a sequence

1. Add a camera using **Camera & lighting**, then return to Shots.
2. Choose **Add shot**. Name it, choose its render camera, and set the first and last Blender frames. Duration includes both endpoint frames and uses the scene's frame rate.
3. Add direction notes for action, expressions, continuity and sound. Notes are production instructions; they do not automatically create character movement. Save performances in Animation and scene motion in Model & animate.
4. Optionally choose featured placed Cast members. An empty selection includes all placed cast. An explicit selection excludes other placed Cast instances from this shot's render snapshot. Native set objects remain present.
5. Duplicate, move up/down or remove cards to arrange the sequence. These are local changes until **Save storyboard**. **Discard draft & reload** replaces local changes with the saved board.

There can be up to 64 shots per scene, 16 selected Cast instances per shot, 2400 frames per shot, and 2000 characters each for direction notes and the generation prompt. The scene's objects and native source are shared, so later scene edits affect future shot snapshots. Independently posed alternate takes require saving their scene/performance variants rather than treating a note as an executed command.

## Render and edit

**Review shot render quote** saves the board, snapshots the selected camera, frame range, cast and source, then opens the existing Deliver/checkout flow. It does not automatically pay or start rendering. Repeated pricing requests use the same request key. A pricing failure can recover the same operation without leaving duplicate render operations.

The snapshot freezes the shot for that operation. Later camera, material, performance or frame edits do not change the queued manifest. The board marks earlier scene revisions; a new snapshot must be requested to render the changed version. Shot renaming, direction notes and board reordering do not themselves change rendered geometry.

After the render completes, the card shows its real status and playable movie. **Add rendered shot to edit** prepares the private media asset through the existing ingestion queue and appends it to the scene's edit. If preparation is still running, choose the action again when ready. The handoff is idempotent and preserves existing music and edits. It uses the shot name in the media library. Add shots in the desired edit order; rearranging storyboard cards does not silently rearrange an existing edit.

## Genesis handoff

Add a generation prompt and choose **Open in Genesis**. AI Studio receives the saved shot's prompt and identity, retains the model/recipe/seed controls, and records the originating shot on generated assets. Existing engine readiness requirements apply. This sprint does not install models or introduce unverified generation recipes. Generated results still use AI Studio's normal **Add result to edit** action.

## Templates and concurrency

Saving a show template and creating an episode copies the board and remaps its camera/Cast IDs to that episode's objects. Render history and request receipts are not copied. Source media retain the existing private access policy.

Board saves use the scene lock and their own board revision. An unchanged board can merge with unrelated scene/script changes. A newer board revision cannot be silently overwritten by an older draft. Server-side validation rejects foreign cameras, cast and scenes.

## Deployment and focused checks

Normal deployment runs migration `20261114160000_register_studio_shots`, which registers `studio.workspace.shots.save` and `.list`, and restarts Rails/workers. No table changes or additional runtime service are required. Browser asset versions/cache advance to v67.

`test/standalone/studio_shots_checks.rb` checks source validation, ordered saves, retries, concurrency, quote snapshots, stale results, template remapping, private handoffs, generation provenance and Dashboard transport. With `LIGHTEK_TEST_BLENDER=1` and `BLENDER_BIN` set, its native proof renders the selected camera for the exact requested frame range, reopens the `.blend`, and probes the resulting MP4.

`test/javascript/studio_shots_test.cjs` checks the real UI module in a DOM fixture, including create/duplicate/reorder/save, a pricing retry, camera/Genesis handoffs and adding finished media to Edit. This is focused implementation verification. Full browser/device, paid-production and cross-workspace acceptance belongs to the integrated verification sprint.
