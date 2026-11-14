# Reuse a production in Live Studio

Open the production's **Deliver** workspace and choose **Use this production in Live Studio**. Live Studio opens for the same site and production scene. You can also open **Production setup · reuse a show or episode** directly in Live Studio and choose a scene from an accessible show template or episode.

## Save and load a setup

1. Choose a production and click **Check saved setup**. An incoming production link checks it automatically, without loading media or starting capture.
2. Configure the existing stage and library controls: prepared Blender/GLB stage, imported camera, camera/session subject placement and chroma key, program image/video, graphic overlay, loop choice, audio bed and volume. Load individual sources to review them in preview if needed.
3. Choose **Save current controls to production**. This saves the selected controls with that scene. It does not save a live session, credentials or device permissions. If another editor changed the scene, check the saved setup again before saving your revision.
4. On a later visit, choose **Load saved setup into preview**. Live Studio rechecks every referenced asset's permissions, site, preparation status and proxy before loading. Sources beyond the initial recent-library list are added to the selectors through this authorized response.
5. Review the program preview and audio levels. Enable camera/microphone or connect the selected session source separately. A session-subject preset chooses how the connected room is composited; it does not join or authorize a room. Start a private test or broadcast through the existing explicit controls when ready.

Loading a saved setup is blocked while broadcasting. It never creates a broadcast, enables camera/microphone or connects a participant room. A failed or cancelled load can leave a partially updated **local** preview; correct the source and review it before starting. Releasing capture cancels the remaining load. Existing holding-screen and program-mix behavior still apply.

## Templates and assets

**Save show template** and **Create episode** copy the scene's `live_preset` with its other editable settings. Changing the episode's layout, placement or levels does not change the template. The referenced assets stay shared library records; copying a setup does not duplicate media or freeze an asset's proxy. Use distinct prepared assets when episodes need independent versions of a set, graphic or audio bed.

This handoff reuses **prepared asset proxies**. It does not build a new GLB from arbitrary scene objects, replay the scene editor's native authoring commands in Three.js, or stream Blender's compositor/simulations. Prepare/export an appropriate stage asset, or render native-only effects into video for library playout. An imported camera index that no longer exists produces an error rather than silently selecting a different saved shot.

The browser Three.js stage and existing library mixer continue to supply the captured program. The native Blender source, rigs and materials remain available in their existing production/asset workflows; this setup does not replace them.

## Storage and access

No migration is required. Scene settings gain `live_preset` version 1 with layout, optional stage/visual/overlay/audio asset IDs, imported camera index, media loop/level and bounded subject controls. URLs, stream keys, device IDs, room tokens and live connection state are excluded. The server rejects unknown fields, invalid switches/numbers, unsupported layouts, wrong media kinds and unavailable assets.

Read/save endpoints are `/dashboard/live/production?site_id=…`, using authenticated same-origin requests, the existing Live entitlement, PWA project/asset access rules and explicit site scoping. Saves use the scene's optimistic lock and preserve its other settings. Responses are private and uncached. Asset playback uses the existing authorized Dashboard proxy for the selected site. These references do not make private assets public.

## Verification

Focused checks exercise real database persistence, stale locks, template/episode independence, asset/site/entitlement restrictions, malformed presets and readiness changes. HTTP checks exercise the actual controller's CSRF, site boundaries and error responses. DOM checks cover explicit preview/save, source controls, safe asset-option creation, on-air rejection and release cancellation. Existing live-page render checks remain in use.

The browser library/stage capture test in CI also loads and saves a production setup through real media/WebGL preview. Chromium cannot launch in the implementation container, so this browser result is not claimed as locally passed. Real device capture, multi-person composition, native-only scene fidelity and destination playback remain in the integrated verification sprint.

See [Browser Live Studio](browser-live.md), [Rooms and audience](session-rooms-and-audience.md), [Native production authoring](production-authoring.md) and the [feature sprint checklist](feature-sprints.md).
