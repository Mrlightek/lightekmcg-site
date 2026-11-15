# Graphical workspace, assistant and rehearsals

Open **Dashboard → Nevaeh**. The central stage holds your work beside the conversation. The illustrated Nevaeh character shows actual request, voice and execution states. The Dashboard assistant dock can answer through the same command pipeline or **Bring this page into workspace**. This is the first reactive virtual-assistant interface; it does not imply a fully rigged 3D character or continuous awareness of every application event.

## Keep the work together

Choose a production to open its saved scene. Switch between **Blocking & rehearsal**, **3D Studio**, **Script**, and **Production work** without leaving the conversation. The scene picker changes the current scene. Guide, workers, learning and task receipts also open as work tabs. Studio remains the actual editable tool, embedded on the stage; its authorization and storage are unchanged.

Up to eight work tabs persist per account. Tabs store resource handles and labels, not a separate copy of your scene or an opt-in personal memory. Resources are authorized again when opened. Close a tab to make room. Internal Dashboard page handles retain only numeric site/scene/project IDs; tokens and other query parameters are not saved. Page-specific permissions still apply inside an embedded page.

The script editor saves the same scene script used by Studio. An unsaved draft stays in the current browser page while you switch tabs. Save it before reloading or leaving; drafts do not survive page reload. If another editor changed the scene, the version check rejects the save. Copy your draft, discard it to reload the current script, reconcile and save again.

The assistant reflects actual request preparation, listening, text-to-speech playback, pending/running jobs and recent failures. It does not display invented progress percentages or inferred emotions. The Dashboard dock uses Converse mode; execution still follows the existing review and authorization behavior. Use the main workspace for Operate mode and detailed receipts.

## Rehearse before applying blocking

1. Open a production and scene. The XY floor plan shows saved characters, props, cameras and listener links in metres. It is an overview, not the rendered perspective view.
2. Drag a character to propose an XY destination, or say **give Amina more space** / **move Amina farther from Bilal** while that production is active.
3. Click **Rehearse scene**, or say **rehearse this scene**. Follow the operation in Production work and watch the private rehearsal video when it finishes.
4. Review corrections and unresolved checks. **Apply verified blocking**, or **apply that rehearsal**, saves a ready result to the original objects only if the source scene has not changed. Rehearsing itself leaves the source untouched.

The contextual phrases above are deliberately narrow commands. Other conversation continues through the existing interpreter. They do not provide arbitrary natural-language scene editing.

Command equivalents, replacing IDs with your owned production, scene and character:

```text
/produce rehearse {"production_id":123,"scene_id":456,"goals":{"789":[2,0]},"preview_seconds":6}
/produce rehearsal_status 987
/produce rehearsal_apply 987
```

A rehearsal forks the saved manifest and pinned Cast/audio sources. It proposes root translation using a bounded half-metre grid, conservative mesh obstacles and reserved character paths. A full source-frame spatial audit checks personal space, collisions, ground/depth and registered head/gaze constraints. Any unresolved audit keeps the result in `needs_attention`, with no apply action. Scene edits make a completed result `stale`; rehearse the new version.

The video is a 384×216 flat-shaded Blender Workbench draft, beginning at the scene start for 1–12 seconds (default six, shortened for smaller scenes). Geometry is audited over the full source scene. The private corrected `.blend` retains the full scene. This preview is marked as a draft and cannot be selected as a finished scene master for episode assembly.

Bounds: 16 characters, 2,400 source frames, XY goals within ±16 metres, up to 4,096 grid visits, 64 path points, 5,000 obstacle triangle bounds per actor and a 180-second Blender process timeout. Large character scale, parented roots, dense colliders, excessive speed or unavailable routes require manual adjustment. Corrected root paths preserve authored rotation keys and source assets; applying a merge exceeding 100 animation keys is rejected. Moving roots still needs a compatible walking/body motion from Cast/Performance. This does not generate footsteps, physically simulate clothing, guarantee eye-bone animation or certify an artistic performance. Moving obstacles and interacting paths can fail the final audit; they are not silently accepted.

A failed operation shows its actual error. Adjust the scene or goals and create a fresh rehearsal. Repeating an identical request key returns its existing operation; changing its inputs with that key is rejected. Ready corrections can be applied once and safely replayed. Applying rechecks ownership, Gatekeeper and source revision.

## Successive dialogue takes

Use the existing `/produce animate` command for each measured dialogue cue. The same speaker reuses the same pinned Cast object; up to 32 non-overlapping takes can be appended in one scene. Each recording is pinned independently. Speaker and listener attention cues follow their take times, and both audio strips and mouth intervals survive native rendering. Overlapping takes for one character are rejected. Explicitly clear the sequence in Performance before replacing it manually.

## Deployment and verification

Apply migration `20261115233000_create_nevaeh_workspaces`, restart Rails and the Studio Sidekiq worker, and retain a working Blender/FFmpeg runtime. The workspace needs no new external service. Existing speech, Cast, Gatekeeper and publishing configuration still apply.

The standalone suite exercises ownership, persistence, optimistic edits, request replay, unchanged-source enforcement, real Blender collision correction, obstacle routing, actual private MP4 duration and dialogue source pinning. Native Blender checks verify two successive recordings and mouth animation intervals. Browser checks exercise the shared workspace, script save, embedded tools, rehearsal command and mobile layout. CI runs the backend/native checks; deployment-specific visual and permissions checks should use your actual saved productions.
