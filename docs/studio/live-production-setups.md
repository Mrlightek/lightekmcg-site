# Reuse a production in Live Studio

Open the production's **Deliver** workspace and choose **Use this production in Live Studio**. Live Studio opens for the same site and production scene. You can also open **Production setup · reuse a show or episode** directly in Live Studio and choose a scene from an accessible show template or episode.

## Save and load a setup

1. Choose a production and click **Check saved setup**. An incoming production link checks it automatically, without loading media or starting capture.
2. Configure the existing stage and library controls: prepared Blender/GLB stage, imported camera, camera/session subject placement and chroma key, program image/video, graphic overlay, loop choice, audio bed and volume. The production setup also saves the panel/presenter/interview/featured layout, title, subtitle, brand, colors and ticker from **Customize layout & branding**. Load individual sources to review them in preview if needed.
3. Choose **Save current controls to production**. This saves the selected controls with that scene. It does not save a live session, credentials or device permissions. If another editor changed the scene, check the saved setup again before saving your revision.
4. On a later visit, choose **Load saved setup into preview**. Live Studio rechecks every referenced asset's permissions, site, preparation status and proxy before loading. Sources beyond the initial recent-library list are added to the selectors through this authorized response.
5. Review the program preview and audio levels. Enable camera/microphone or connect the selected session source separately. A session-subject preset chooses how the connected room is composited; it does not join or authorize a room. Start a private test or broadcast through the existing explicit controls when ready.

Loading a saved setup is blocked while broadcasting. It never creates a broadcast, enables camera/microphone or connects a participant room. A failed or cancelled load can leave a partially updated **local** preview; correct the source and review it before starting. Releasing capture cancels the remaining load. Existing holding-screen and program-mix behavior still apply.

## Carry the show look between rooms

A version 2 setup includes portable show presentation fields. Loading applies these fields locally to a connected session compositor, preserving the room's featured participant, guest names/roles and camera effects. If no room is connected, the show look waits locally and applies when you connect one. Changing the selected room keeps the show look but uses that room's participant settings. If a loaded 3D stage uses the session as its subject, connecting the room keeps the stage program view.

**Use this room’s saved presentation** reloads the chosen room's authorized state, clears the local show override and restores its saved look. This does not change the saved production setup. Editing layout/branding while a show override is active updates that local override; save the production setup to retain those edits for later episodes.

Loading/restoring styling never writes a room's presentation. **Save this room’s presentation** remains the separate, explicit room-save action. Production setups exclude participant maps, featured user IDs, room keys, room tokens and admission state. A show template cannot select or rename guests in a different room through its styling fields.

When a connected room source used by the program or a 3D-stage subject disconnects, holding screen activates. Browser capture and real multi-person delivery remain part of integrated acceptance.

## Templates and assets

**Save show template** and **Create episode** copy the scene's `live_preset` with its other editable settings. Changing the episode's layout, placement or levels does not change the template. The referenced assets stay shared library records; copying a setup does not duplicate media or freeze an asset's proxy. Use distinct prepared assets when episodes need independent versions of a set, graphic or audio bed.

This handoff reuses **prepared asset proxies**. It does not build a new GLB from arbitrary scene objects, replay the scene editor's native authoring commands in Three.js, or stream Blender's compositor/simulations. Prepare/export an appropriate stage asset, or render native-only effects into video for library playout. An imported camera index that no longer exists produces an error rather than silently selecting a different saved shot.

The browser Three.js stage and existing library mixer continue to supply the captured program. The native Blender source, rigs and materials remain available in their existing production/asset workflows; this setup does not replace them.

## Storage and access

No migration is required. The scene’s `live_preset` version 1 retains its original stage/media contract. Version 2 adds a `presentation` object with only `layout`, `title`, `subtitle`, `brand`, `ticker`, `background` and `accent`. It reuses the existing room presentation normalizer for supported layouts, text bounds and colors. Both versions retain layout, optional stage/visual/overlay/audio asset IDs, imported camera index, media loop/level and bounded subject controls. URLs, stream keys, device IDs, room tokens and live connection state are excluded. The server rejects unknown fields, invalid switches/numbers, unsupported layouts, wrong media kinds and unavailable assets.

New saves use version 2 when show styling is available. Version 1 setups still read/load, without a presentation override. A version 1 write cannot overwrite an existing version 2 setup and discard its styling; reopen the updated Live Studio before saving. Deploy the scripts and server together.

Read/save endpoints are `/dashboard/live/production?site_id=…`, using authenticated same-origin requests, the existing Live entitlement, PWA project/asset access rules and explicit site scoping. Saves use the scene's optimistic lock and preserve its other settings. Responses are private and uncached. Asset playback uses the existing authorized Dashboard proxy for the selected site. These references do not make private assets public.

## Verification

Focused checks exercise real database persistence, stale locks, template/episode independence, asset/site/entitlement restrictions, malformed presets and readiness changes. HTTP checks exercise the actual controller's CSRF, site boundaries and error responses. DOM checks cover explicit preview/save, source controls, safe asset-option creation, on-air rejection and release cancellation. Show-style checks also cover version 2 persistence/episode independence, identity-field rejection, downgrade protection, room switching/restoration and actual compositor draw commands. Existing live-page render checks remain in use.

The browser library/stage capture test in CI also loads and saves a production setup through real media/WebGL preview, and exercises show-style application/restoration with a simulated room transport. The presentation renderer check exercises portable styling on a real canvas. These transport fixtures do not verify a deployed LiveKit server or actual participant devices. Chromium cannot launch in the implementation container, so this browser result is not claimed as locally passed. Real device capture, multi-person composition, native-only scene fidelity and destination playback remain in the integrated verification sprint.

See [Browser Live Studio](browser-live.md), [Rooms and audience](session-rooms-and-audience.md), [Native production authoring](production-authoring.md) and the [feature sprint checklist](feature-sprints.md).
