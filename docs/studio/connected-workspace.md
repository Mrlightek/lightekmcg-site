# Work inside one production

Open **Dashboard → Studio**, then open a production scene. The production name, scene selector and navigation stay in place as you work.

| Section | What you do |
| --- | --- |
| Stage | Arrange the cast and set in the interactive 3D viewport. Select an object to position it or attach a recording. |
| Edit | Assemble picture and sound, trim/split clips, adjust color, mix tracks and add titles. |
| Cast | Create or register a performer, place it in the scene and save dialogue/singing, facial cues and gestures. |
| Music | Write beats and instrument notes. Keep the source editable and add/update its mix in the episode edit. |
| Script | Write the scene and shot notes, with optional Nevaeh writing assistance. |
| Deliver | Quote/export and publish finished artifacts through the existing release flow. |

**Model & animate** opens object, mesh, sculpt, rig, animation and node tools for this scene. **Camera & lighting** keeps the scene outliner beside camera, visual and render controls. **Assets** opens the shared library inside the production shell.

The scene selector changes scenes inside the same project. Script/shot notes, timeline edits and musical drafts survive section and scene changes in the current browser session. Unsaved cast direction survives switching sections and performers. These drafts are not durable until saved: use **Save changes** in Edit, Music or Script, and the relevant **Save performance**, **Save element** or **Save visual settings** form for object/cast/camera changes. The save indicator identifies unsaved drafts; closing the browser warns about them. Browser history and links retain the selected section.

## Bring a rendered shot into the episode

1. Direct and save a cast performance, or compose an animated scene.
2. Request the full-shot export quote and complete its existing checkout. The worker must complete the render before it can be used.
3. Open **Renders & handoffs** at the bottom of any section. Refresh to inspect the project's actual operations, errors and finished artifacts. An open tray refreshes while renders are pending or running.
4. Choose **Add to edit** beside a completed shot. If preparation is still running, the status explains that; choose the action again to check it. Failed media preparation reports its error.
5. When ready, Studio opens Edit with the shot placed after the existing picture. A music track does not push the first shot to the end of the song. The first picture uses a separate track from the score. Retries reuse the same media asset and placement receipt, avoiding duplicate clips.

The handoff saves an unsaved edit first. If another editor changed the scene, the optimistic lock reports the conflict instead of overwriting it. Draft previews remain visibly marked and cannot enter through this finished-shot handoff.

## Current boundaries

This change unifies the existing Dashboard production tools and the render-to-edit workflow. It does not install facial replacement or neural lip-sync engines, provide desktop Blender/Resolve parity, or join a project's separate scenes into a single automatic episode master. Cast mouth automation remains recording-volume driven with explicit face/gesture cues. Rendering, payment and publication still use their existing workers and acceptance requirements.

## Verification

`test/javascript/studio_dashboard_browser_test.cjs` runs the native modules and real WebGL viewport in Chromium with scoped API fixtures. It checks all sections at 1440, 1024 and 390 pixels, persistent production chrome, scene draft isolation, saving, render preparation/retry and handoff into Edit. Screenshots go to `tmp/studio-dashboard-browser/`.

`test/standalone/studio_production_checks.rb --name /test_production_/` uses real Active Record/Active Storage and the production worker to verify the handoff, receipt retries, picture/music placement, account/project access, stale writes and draft-preview exclusion. Live paid rendering and authenticated production use remain deployment acceptance steps.

Deployment registers `studio.workspace.artifact.use` through the normal migration/seed pipeline. Restart the web and worker processes through the existing release pipeline. Dashboard assets and the shared PWA cache advance to version 60.
