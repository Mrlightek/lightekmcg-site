# Spatial editor React/TypeScript reference

This is a typechecked component/state/synchronization reference for Lightek's next editor shell. It is **not mounted into the Rails PWA** and does not claim the proposed Blender/WebRTC service exists. The shipping vanilla-JS Spatial / 4D workspace is separate. Integrate this as a React island once its backend transport adapters are implemented, without rewriting the rest of the PWA.

## Stack and module boundaries

- React + TypeScript for panels and controls; Dockview for docked/tabbed/resizable desktop workspaces.
- Zustand for small selector-based UI subscriptions and serializable project state. Keep RTCPeerConnections, Three.js objects, video frames, media streams and workers in runtime refs/services.
- Radix primitives for accessible sliders, dialogs, menus and switches, styled with Lightek's Tailwind/CSS tokens. The minimal shell here uses plain CSS and native controls; it does not pull in a second component design system.
- TanStack Virtual for large asset bins and track rows; draw dense keyframes/waveforms on canvas and index their hit targets. Avoid one React element per waveform sample/keyframe.
- Existing Three.js/MediaPipe modules for the runtime. React schedules controls, not the per-frame render loop.

```text
src/
  EditorShell.tsx        dock layout + compact navigation + integer-frame ruler
  editor.css            dark neutral panels, Lightek gold, focus and density tokens
  timeline.ts           discriminated tracks, rational frame times, local evaluation
  store.ts              serializable project/UI state
  TimelineSync.ts       coalesced seeks + revisioned decoded-frame acceptance
  WebSocketPreviewTransport.ts  typed demand → wire-envelope mapping and backpressure
  ThreeTimelineAdapter.ts       animation mixers / Object3D transforms / camera hooks
  TimelineSync.test.ts  timing, stale frames, camera cuts, lifecycle regression
```

Host modules to add during integration:

- `ViewportPanel`: decoded-frame receiver, held color/depth base layer, webcam compositor, gizmo pass, frame-age/status overlays.
- `CameraDock`: active shot camera, lens/focus/aperture/light controls with local draft state, explicit commit and acknowledgement. Disable unavailable camera properties with an explanation.
- `AssetLibrary`: prepared/processing/failed asset tiles, source previews, drag-and-drop typed placement intent, generation job progress and a Nevaeh prompt/plan review UI. Only advertise GLTF/USD/OBJ staging when its actual ingestion adapter exists.
- `SpatialTimeline`: video/audio rows, transform keyframes, camera-cut track, snapping, markers, selection/trim and keyboard controls.
- `WebRtcReceiver`: authenticated signaling, decoder frame/timestamp association and bounded frame ownership; not a renderer or project store.
- `CapabilityCommands`: Gatekeeper mutation receipts, expected revisions, reconnection and conflict handling.

`EditorShell` receives those real panel components as slots. There are no fake generator controls or placeholder backend actions. Dockview owns desktop geometry. Under 900 px, use a single focused work area and explicit Stage/Assets/Cameras/Timeline navigation; preserve editor runtime/project ownership outside panel mounts. Persist the dock layout by workspace/user using Dockview serialization, separately from the production scene.

## Layout behavior

Desktop: assets left (about 260 px), stage center, cameras right (about 300 px), timeline below the stage (about 240 px). Keep the stage largest; expose full-screen/focus modes and collapsible rails. Status reports connection, requested frame, displayed frame, render lag and unsaved edits. Do not label a stream “sub-50 ms” unless that session has measured telemetry supporting it.

The viewport may expose a hidden `<video playsInline>` as the WebRTC decode source, a compositor canvas and a gizmo/annotation pass. A raw DOM video underneath a transparent canvas is sufficient for simple handles, but **shared depth occlusion needs color/depth/webcam in the same compositing coordinate system and WebGL pass**. Prefer one Three.js renderer with explicit composition/gizmo passes over multiple unrelated renderers. `ResizeObserver` updates viewport dimensions and interaction coordinates.

Maintain two camera concepts: the saved Blender **shot camera** and the local **viewer/parallax camera**. Head tracking must not silently rewrite a user's shot lens or create animation keyframes. “Bake viewer motion” is an explicit output action. A hand/face overlay is local data, not a reason to dirty the saved scene on every frame.

## State model

`Project` uses integer timeline frames and a rational frame rate (`30000/1001`, not the rounded number `29.97`). The UI uses zero-based timeline frames; `blenderFrameStart` maps these to Blender scene frames (`blenderFrame = blenderFrameStart + requestedFrame`). Requests and displayed-frame metadata carry both so a scene starting at frame 1 does not acquire a one-frame scrub error. The server validates that mapping against its canonical scene settings. Media clips carry their own source frame rate and in point. Frame positions are serialized as integers; derived microseconds use BigInt internally and are not serialized into JSON. Transform tracks use quaternions for rotation interpolation. One authoritative camera-cut track avoids competing camera choices.

A project load normalizes/sorts keyframes once. Transform sampling uses binary search. For very large projects, also index active clip intervals/camera cuts and cache evaluation plans instead of scanning every track on every render. Project state should be immutable; edits produce a new revision after Gatekeeper acknowledgement.

Important state fields:

```ts
requestedFrame: number;       // Where the user moved the playhead.
displayedFrame: number|null;  // Frame whose pixels have actually been accepted/presented.
requestedSeq: number;         // Invalidates previous in-flight preview requests.
displayedRevision: number|null;
pending: boolean;
```

Source audio time uses the shared timeline clock. During playback, use an AudioContext/media clock (or another designated master clock) and derive the integer display frame; do not accumulate timing from `setInterval` ticks. Scrubbing pauses/silences playback and evaluates exact timeline positions. HTMLMediaElement `currentTime` alone is not proof of frame-exact source decoding: use indexed WebCodecs decoding where exact local video frame selection is required, and confirm backend Blender frames from their metadata.

## Scrub → local scene → backend → visible frame

```ts
const localSceneAdapter = new ThreeTimelineAdapter({
  objects: sceneObjectsById,
  mixers: gltfAnimationMixers,
  selectShotCamera: setActiveShotCamera,
  seekMedia: sourceDecoder.seekTimelineMedia,
  setGhostPicking: setGizmosPending,
  applyPresentedMatrices: applyServerCameraMatrices,
});
const previewTransport = new WebSocketPreviewTransport(authenticatedPreviewSocket);
const sync = new TimelineSync(store, localSceneAdapter, previewTransport, sessionId);

// pointer/keyboard movement: local evaluated transforms/media/camera update now.
sync.seek(frame);
// pointer release: send the final exact position without waiting for debounce.
sync.seek(frame, true);

// Called ONLY after receiver matched metadata to this actual decoded media frame.
sync.acceptDecodedFrame({
  metadata,
  present: () => compositor.copyAndClose(decodedFrame),
  discard: () => decodedFrame.close(),
});
```

The sequence is:

1. Clamp/round the timeline frame, evaluate transform interpolation, source clip positions and the active camera locally.
2. Update local proxies and the playhead immediately. Ghost pending gizmos and disable precise server-image picking while the background is stale.
3. Replace the pending preview demand and send at most one every 50 ms while scrubbing. A final pointer/keyboard release flushes the exact last frame immediately. This example's 20 Hz request budget is configurable and is distinct from renderer/video fps.
4. The server's proposed preview coordinator coalesces demands, applies the accepted scene revision and calls `scene.frame_set(frame)`, then renders the requested camera.
5. Receiver associates the actual decoded frame with session, scene revision, request sequence, frame, camera ID and camera matrices. Metadata arrival alone is not presentation.
6. Only a matching decoded frame may replace the held compositor base layer. The controller updates `displayedFrame` after presentation; stale frames are closed/discarded.

A visible raw WebRTC `<video>` element advances by itself; merely ignoring old metadata does **not** prevent its pixels from appearing. The reference therefore requires a receiver/frame gate and an explicit `present()` callback. Pair color/depth by the same frame ID and hold the last coherent image during buffering. Do not claim frame-accurate scrubbing by relabeling a stale video.

Use `requestVideoFrameCallback`/WebCodecs receiver capabilities where supported and associate media timestamps with server metadata. Do not pair every decoded frame with the most recently received side-channel message. Bound any pairing buffer and define a deadline; drop unmatched frames. The wire adapter maps the typed demand to the proposed snake-case server protocol and rejects disconnected/congested control channels. It does not create a new unauthenticated WebSocket endpoint.

The frame adapter owns copying/closing resources and `discard()` must be idempotent.

`alignToPresentedCamera` uses the server view/projection matrices so gizmos project into the actual rendered shot. Gizmo drag updates local draft transforms; pointer release submits a durable Gatekeeper command. That acknowledgement updates project revision, then `replaceProject()` requests a fresh preview. Timeline seeks and face poses are ephemeral; they do not write keyframes or advance the database revision.

If transport send fails, show the error and keep pending state. On reconnection, establish a fresh session/controller, fetch the canonical snapshot and reissue the latest requested frame. Dispose the old controller; do not accept old-session frames. Durable command IDs and scene-version conflicts belong in the capability adapter, not the ephemeral preview sender.

## Running the reference checks

```sh
npm ci --prefix examples/spatial-editor
npm --prefix examples/spatial-editor run check
npm --prefix examples/spatial-editor test
```

The tests cover rational frame timing, media in points, local transform interpolation, camera cuts, seek coalescing/final flush, session/revision/sequence/camera/frame mismatches, failed presentation, scene revisions and teardown. They test the state contract, not a deployed WebRTC transport or a full interactive editor.

See `docs/studio_spatial_4d.md` for the browser engine/protocol and `docs/studio_realtime_subsystems.md` for GPU streaming, depth and Text-to-Stage design.

Primary references:
- https://dockview.dev/docs/overview/quickstart/?framework=react
- https://dockview.dev/docs/core/panels/add/
- https://zustand.docs.pmnd.rs/
- https://www.radix-ui.com/primitives/docs/overview/accessibility
- https://tanstack.com/virtual/latest/docs/introduction
