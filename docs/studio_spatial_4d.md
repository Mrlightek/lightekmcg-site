# Lightek Spatial / 4D: browser implementation and Blender preview protocol

## Delivery status

The first browser slice is implemented in the Studio **Spatial / 4D** tab. It contains webcam video textures, calibrated head parallax, an off-axis window projection, person segmentation and layered displacement, up to four video sources, recorded-angle offset/scrub/drift correction, crossfades, an orbitable spatial array, scene geometry loading, video-only recording, and authenticated import of that recording into the existing media library.

The persistent headless Blender preview service, WebRTC media transport, RGB-depth frame pairing, remote interactive sessions, arbitrary-view reconstruction, audio mixing in the browser recorder, and Blender-quality spatial export are **designed below, not implemented by this browser slice**. Existing durable scene edits, queued Blender draft previews, timeline exports, library publication and live-library sources remain available.

The application does not promise true volumetric capture from an ordinary webcam. Face scale estimates relative viewer distance; a foreground mask produces 2.5D layering. A viewer moving around an opaque, flat video cannot discover geometry that was never captured. Extra camera views, depth layers or scene meshes supply that information.

## Modules

| Module under `public/lightek/` | Responsibility |
| --- | --- |
| `studio-spatial.js` | Studio tab, saved scene settings, authenticated recording upload, mount/dispose bridge |
| `spatial/experience.js` | UI state, user gestures, calibration, animation loop, lifecycle |
| `spatial/projection.js` | Pure frustum math, eye-span calibration, bounded/smoothed head pose |
| `spatial/video-sources.js` | Webcam ownership, video loading, source offsets, drift correction, cleanup |
| `spatial/tracker.js` | One frame in flight, 10 Hz inference budget, model/error/timeout handling |
| `spatial/vision-worker.js` | Local MediaPipe FaceLandmarker + SelfieSegmenter inference |
| `spatial/compositor.js` | Three.js renderer, VideoTextures, mask shader, displaced planes, crossfade/array |
| `spatial/scene-content.js` | Studio primitive/native GLB geometry adapter, Blender Z-up → window Y-up |
| `spatial/output.js` | Bounded MediaRecorder output and download lifecycle |

The UI and engine use vanilla JS and ES modules. The vision worker intentionally has a classic-worker shell with a dynamic ESM import: the pinned MediaPipe WASM loader uses `importScripts`, which module workers reject. Dependencies are pinned to `@mediapipe/tasks-vision@0.10.32`; WASM downloads from jsDelivr and model version `1` downloads from Google. Inference and webcam frames stay in the browser. Strict deployments must permit those download origins or host the pinned files locally and replace the three URLs in `vision-worker.js`.

No camera is requested on mount. Start, calibration, recording and uploading each have an explicit UI action. Leaving the workspace, hiding the tab, or leaving the page releases capture. The browser must provide WebGL for this workspace; the regular 3D Layout can still use its software fallback.

## Build and verify iteratively

1. Open a saved Studio scene → **Spatial / 4D**. The foreground cube and background knot demonstrate depth before any camera access.
2. Press **Start webcam**, then **Enable tracking**. Enter approximate eye distance and physical viewport width under calibration. Face the webcam and press **Calibrate head position**. Move left/right/up/closer; the screen plane stays fixed while scene perspective changes.
3. Enable **Person cutout + layered 2.5D displacement**. The foreground mask controls alpha and a small mesh displacement. It does not estimate a full body depth map.
4. Add up to four total sources (the webcam counts as one). Align recorded angles with per-source start offsets, press Play and switch views. Use **Spatial array** + **Orbit** to inspect the feeds in space. Live webcam streams are not seekable or frame-synchronized with recorded clips.
5. Press **Bring this Blender scene into the window** to load the current scene's primitives and prepared native GLB proxy, including saved native transforms/hiding/material overrides where available. Scene geometry is fitted into the window; browser appearance is not identical to a Blender final render. Save workspace preserves calibration/display settings, not local file handles or camera streams.
6. Record the composition, stop, and download or **Save recording to Lightek library**. Browser-supported MP4 is preferred, otherwise WebM. This first recorder is video only and stops at 180 seconds or approximately 200 MB. Add audio and export MP4 through the existing timeline workflow when required for OTT. Existing Library publication and Live Studio library-source controls consume the resulting asset after ingestion finishes. Recording a parallax performance bakes that camera movement into ordinary video; third-party players do not gain viewer-specific head tracking.

### Minimal video-texture setup

```js
import * as THREE from '/lightek/vendor/three/three.module.js';

// Call from a user action on HTTPS. Keep `stream` and release it on teardown.
const stream = await navigator.mediaDevices.getUserMedia({video: true, audio: false});
const video = document.createElement('video');
video.muted = true;
video.playsInline = true;
video.srcObject = stream;
await video.play();
const texture = new THREE.VideoTexture(video);
texture.colorSpace = THREE.SRGBColorSpace;
const mesh = new THREE.Mesh(
  new THREE.PlaneGeometry(0.45, 0.45 * video.videoHeight / video.videoWidth),
  new THREE.MeshBasicMaterial({map: texture, side: THREE.DoubleSide})
);
mesh.position.z = -0.3;
scene.add(mesh);
// Teardown: video.pause(); stream.getTracks().forEach(t => t.stop());
// texture.dispose(); mesh.geometry.dispose(); mesh.material.dispose();
```

### Off-axis math

The physical window is centered on world `z = 0`, with width `W`, height `H`, Y up. The viewer eye is `E = (ex, ey, ez)`, with `ez > near > 0`. Scene content lies behind the window. The frustum at the near plane is:

```text
left   = (-W/2 - ex) * near / ez
right  = ( W/2 - ex) * near / ez
top    = ( H/2 - ey) * near / ez
bottom = (-H/2 - ey) * near / ez
```

```js
import {applyWindowProjection} from '/lightek/spatial/projection.js';

// Every animation frame, AFTER resize and instead of updateProjectionMatrix():
applyWindowProjection(camera, smoothedEye, windowWidthMeters, windowHeightMeters);
renderer.render(scene, camera);
```

`applyWindowProjection` translates the camera to the eye, keeps its orientation aligned with the window, builds `projectionMatrix.makePerspective(left, right, top, bottom, near, far)` and updates the inverse matrix. **Do not also `lookAt(windowCenter)` or run OrbitControls in this mode**: those rotate the view and defeat the fixed physical-window constraint. Orbit is a separate explicit mode.

### MediaPipe → calibrated eye

```js
import {HeadPose, faceMeasurement} from '/lightek/spatial/projection.js';
import {FaceTracker} from '/lightek/spatial/tracker.js';
const pose = new HeadPose({distance: 0.6, mirror: true});
let measured = null;
const tracker = new FaceTracker({
  onStatus: console.log,
  onResult: ({landmarks}) => {
    measured = faceMeasurement(landmarks, video.videoWidth / video.videoHeight);
  }
});
tracker.start();
// On Calibrate, once a face is visible:
pose.calibrate(measured);
// In the animation loop:
tracker.sample(video, performance.now());
const target = pose.estimate(measured, video.videoWidth / video.videoHeight);
if (target) applyWindowProjection(camera, pose.smooth(target, deltaSeconds), W, H);
// Teardown: tracker.stop();
```

Eye-center displacement gives X/Y. Relative apparent eye span gives distance `z = calibratedDistance * calibratedEyeSpan / currentEyeSpan`. This is a scale estimate, not the raw normalized MediaPipe landmark Z interpreted as meters. Head rotation and unknown webcam optics affect it. The implementation bounds the estimate, smooths it and recenters when the face is lost; absolute metric tracking would require a camera/physical calibration procedure.

## End-to-end server architecture

Keep Rails/Nevaeh/Gatekeeper as the scene authority. A preview coordinator manages persistent Blender sessions and delegates encoded media to a transport sidecar. Do not expose Blender's Python interpreter as an internet API.

| Path | Transport | Semantics |
| --- | --- | --- |
| Project/asset mutations | Existing authenticated Gatekeeper command API; reliable acknowledged control channel later | Durable, authorized, revisioned, idempotent; never silently discarded |
| Viewer pose / preview demand | Latest-value WebSocket or unordered WebRTC data channel | Ephemeral; coalesce by session; stale demands can be dropped |
| Job progress, conflict, rendered-frame metadata | Authenticated WebSocket / ActionCable | Ordered events carrying command ID and scene revision |
| Interactive rendered video | WebRTC sender sidecar → browser video tracks | Low-latency preview; adaptive resolution and camera subscriptions |
| First MVP rendered image bundles | Existing queued Blender draft preview, followed by a persistent worker HTTP/WS frame-bundle endpoint | Easiest verifiable command → pixels loop; bounded work and explicit latency |
| Completed movies/posts/OTT masters | Existing operation/artifact + FFmpeg + library/publication pipeline | Durable files; existing render quotes and publish controls |
| Audience delivery | HLS/DASH/OTT from existing publication/broadcast infrastructure | Scalable playback, not a low-latency scene-control loop |

WebRTC signaling travels through the authenticated control service. A media sidecar handles ICE/STUN/TURN and congestion control. Use a persistent worker per active scene session/pool allocation; final-quality jobs stay in a separate queue. A worker reloads the canonical scene snapshot after restart and replays acknowledged edits to the chosen revision.

### Proposed control envelope

The following schema is a new preview-session contract, not an assertion that these endpoints already exist. Existing capabilities remain the integration boundary.

```json
{
  "v": 1,
  "type": "command",
  "session_id": "preview-session-id",
  "command_id": "client-generated-uuid",
  "scene_id": 42,
  "base_revision": 81,
  "client_seq": 17,
  "op": "object.transform",
  "params": {
    "object_id": 9,
    "location": [1.0, 0.0, 2.0],
    "rotation_degrees": [0.0, 0.0, 30.0],
    "scale": [1.0, 1.0, 1.0]
  }
}
```

```json
{
  "v": 1,
  "type": "ack",
  "command_id": "client-generated-uuid",
  "scene_id": 42,
  "revision": 82,
  "status": "applied",
  "preview_status": "queued"
}
```

The database mutation acknowledgement means the edit is saved; it does not mean a new frame is visible. A duplicate command ID returns its original receipt. A stale `base_revision` returns `conflict` plus current revision; the client fetches the new snapshot and explicitly reconciles pending edits. Scene units are meters, Blender is right-handed Z-up, rotations in the wire format above are degrees; adapters convert to Blender radians and browser Y-up. Camera intrinsics, frame rate and timeline time are explicit.

Existing `studio.scene_object.transform`, `studio.workspace.blender.object.save`, camera save, asset placement and workspace capabilities supply durable edits today. Preview session open/close/subscribe and ephemeral frame/pose demands are new capabilities to register through the same Nevaeh/Gatekeeper system. Reusing a capability is not bypassing its existing access or payment rules.

The session handshake must also fix window width/height and a `window_to_blender` transform (including unit scale and matrix storage order). Viewer eye coordinates are local to that window; do not copy browser Y-up values directly into Blender Z-up coordinates. For a Blender off-axis camera, derive lens/sensor fit/lens shifts from the required frustum and compare `calc_matrix_camera` against the reference projection before claiming accurate server/client matching.

A separate ephemeral demand might be:

```json
{
  "v": 1,
  "type": "preview.demand",
  "session_id": "preview-session-id",
  "request_seq": 104,
  "scene_revision": 82,
  "frame": 144,
  "camera_ids": [3, 4],
  "quality": {"width": 640, "height": 360, "samples": 8},
  "viewer": {"space": "window-y-up-meters", "eye": [0.04, 0.0, 0.6]}
}
```

Keep only the newest pending preview demand. Do not enqueue every mouse move or face frame as a durable render job. Retain all accepted durable edits; a latest-value policy applies to preview requests only. A worker already rendering revision 81 can finish or be cooperatively cancelled; it must never label that image revision 82.

### Frame / multi-angle contract

```json
{
  "v": 1,
  "type": "preview.bundle",
  "session_id": "preview-session-id",
  "request_seq": 104,
  "scene_revision": 82,
  "bundle_id": "82-144-104",
  "frame": 144,
  "fps": {"numerator": 24, "denominator": 1},
  "views": [
    {"camera_id": 3, "frame_id": "82-144-104-3", "color_url": "authenticated-short-lived-artifact-url", "depth_url": null},
    {"camera_id": 4, "frame_id": "82-144-104-4", "color_url": "authenticated-short-lived-artifact-url", "depth_url": null}
  ]
}
```

All views in a bundle use the same timeline frame and frozen scene revision. A single Blender worker renders arbitrary cameras sequentially; four cameras generally cost more than one. Initially subscribe to an active camera plus a neighboring view. Increase concurrent camera workers only after measuring GPU/memory limits. Client swaps a complete, decodable bundle atomically, rejects stale revisions/request sequences, and keeps the previous visible frame while waiting.

For WebRTC, map each camera ID to a negotiated track. Carry equivalent revision/frame/camera metadata and a media timestamp association on the control channel. Do not assume independent video element `currentTime` values are frame-exact synchronization. Production multi-angle playback needs a common capture clock and aligned media timestamps/keyframes; the browser prototype's offset/drift correction is approximate.

For RGB-depth rendering, pair the color and depth by frame ID and carry camera projection/view matrices, clip planes, resolution, depth convention and units. Use linear depth in meters or document the exact inverse projection. Never combine color from one revision with depth from another. If depth is absent, show the color plane without pretending it supports correct view reprojection. Transparent RGBA/layered output is useful for webcam/background compositing but still does not contain hidden surfaces.

## Existing API loop available before a streaming service

The current implementation already supplies durable transforms and a queued, small Blender camera preview. The following minimal client sketch uses those existing capability names; it renders the active saved Blender camera, not a new multi-camera stream:

```js
await nevaeh.execute({
  capability: 'studio.scene_object.transform',
  payload: {scene_id: sceneId, object_id: objectId,
    attributes: {location: [1, 0, 2], rotation: [0, 0, 30], scale: [1, 1, 1]}}
});
let preview = (await nevaeh.execute({
  capability: 'studio.workspace.blender.preview',
  payload: {scene_id: sceneId, frame: 144}
})).result;
while (['pending', 'running'].includes(preview.status)) {
  await new Promise(resolve => setTimeout(resolve, 1000));
  preview = (await nevaeh.execute({
    capability: 'studio.workspace.blender.preview',
    payload: {scene_id: sceneId, operation_id: preview.operation_id}
  })).result;
}
if (preview.status !== 'completed') throw new Error(preview.error || 'Preview failed');
const texture = await new THREE.TextureLoader().loadAsync(preview.url);
texture.colorSpace = THREE.SRGBColorSpace;
// Display texture on a background plane; dispose the previous texture when replacing it.
```

Production UI must stop polling when its scene/session changes and display the actual operation status. This is the baseline round trip to measure, not a claim of interactive frame rate. The persistent-session protocol above removes repeated process/scene setup and adds coherent revisioned multi-camera output.

## Persistent Blender Python structure

Reuse `blender/runner.py` and its manifest/native-template/camera configuration functions for scene staging. Extract reusable staging functions from its one-shot `main()` rather than cloning its material, node and asset code into a new implementation. Keep these responsibilities in a preview worker:

```python
# Structural outline for a NEW worker, not a registered production endpoint.
# Network/encoder I/O belongs in the coordinator and sidecar, not bpy render callbacks.
import bpy
from queue import Queue, Empty

commands = Queue()             # Reliable accepted mutations, ordered by revision.
latest_preview = None          # Replaced by a newer ephemeral demand.
current_revision = 0


def apply_accepted_edit(edit):
    global current_revision
    # Resolve IDs through the canonical scene-object mapping built during staging.
    obj = object_map[edit['object_id']]
    if edit['op'] == 'object.transform':
        obj.location = edit['location']
        obj.rotation_euler = degrees_to_radians(edit['rotation_degrees'])
        obj.scale = edit['scale']
    # Other named operations: camera properties, asset placement, animation values.
    current_revision = edit['revision']
    bpy.context.view_layer.update()


def render_bundle(demand):
    if demand['scene_revision'] != current_revision:
        return emit_revision_mismatch(demand, current_revision)
    scene = bpy.context.scene
    scene.frame_set(demand['frame'])  # Same animation evaluation for every camera.
    configure_preview_quality(scene, demand['quality'])
    outputs = []
    for camera_id in demand['camera_ids']:
        scene.camera = camera_map[camera_id]
        scene.render.filepath = private_temporary_frame_path(demand, camera_id)
        bpy.ops.render.render(write_still=True)
        outputs.append(atomically_publish_frame(scene.render.filepath, demand, camera_id))
    emit_complete_bundle(demand, current_revision, outputs)


def tick():
    # Called on Blender's MAIN thread. Coordinator I/O runs in a separate PROCESS.
    while True:
        try:
            apply_accepted_edit(commands.get_nowait())
        except Empty:
            break
    demand = take_latest_preview_demand()
    if demand:
        render_bundle(demand)
    return 0.01
```

The host must keep the Blender process alive and drive its main-thread event loop. `bpy.app.timers.register(tick)` alone does not guarantee a background `--python` process stays alive after its script exits. A persistent foreground service can use Blender's timer loop; a dedicated headless worker can instead own an explicit main-thread command loop polling bounded, non-blocking IPC from the coordinator process. Keep network reading/encoding in separate processes; do not run a Python reader thread alongside bpy rendering. Only immutable envelopes cross the IPC queue. Rendering is blocking; cancellation is cooperative between camera/frame renders unless the coordinator restarts the worker.

Scene staging order: load the prepared .blend → map stable object/camera IDs → apply saved transforms/materials/rig parameters → evaluate animation frame → apply camera intrinsics/active camera → render requested camera bundle → deliver metadata after artifacts exist. Animation edits change keyframes/actions; timeline scrubbing evaluates `scene.frame_set` without inserting keyframes.

For faster transport, replace temporary PNG bundles with a bounded shared-memory/frame pipe and an encoder sidecar (GStreamer/FFmpeg/aiortc after deployment testing). WebRTC does not make Blender rendering instant: interactive performance depends on scene complexity, engine, samples, resolution, camera count and GPU allocation. Measure command acknowledgement, queue delay, render time, encode time, network latency and displayed frame age separately. Full-quality Cycles output remains an asynchronous paid render/export operation.

## MVP roadmap and acceptance

| Step | Delivery | Acceptance |
| --- | --- | --- |
| 1 · implemented browser slice | Head-parallax window, webcam/mask compositing, local angles, geometry, recording/library import | Pure projection tests; actual Three.js image changes; real MediaPipe/WASM landmarks and mask; recorded video decodes; camera tracks end on teardown |
| 2 · canonical edit → one Blender camera | Existing transform command followed by existing queued Blender draft preview | Saved edit revision matches the image's staged manifest; known geometry visibly moves |
| 3 · persistent preview worker | Session coordinator + snapshot/delta apply + newest preview demand | Warm worker handles repeated edits without scene reload; stale demands skipped; session closes and resources released |
| 4 · frozen multi-camera bundles | One timeline frame, two cameras, atomic client swap | Both views carry identical frame/revision; switching keeps the displayed action aligned |
| 5 · WebRTC transport | Signaling + media sidecar + camera subscriptions | Real client decodes the active rendered camera; reconnect and track replacement preserve session/revision correctness |
| 6 · hybrid depth/layers | Paired RGB/alpha/depth and browser reprojection | Depth-aware occlusion and parallax verified against a known rendered scene, with explicit missing-depth behavior |
| 7 · production/broadcast | Record or server-compose agreed output; timeline/audio/MP4 master; existing publish and Restream/Gatekeeper routes | A generated artifact is consumed by the real publication/live pipeline; no claim of platform delivery from local preview alone |

The sequence keeps the first measurable server MVP small: **client transform → Gatekeeper acknowledgement → Blender re-stage → changed camera frame displayed**. Prove that loop before adding low-latency encoding and more angles.

## Verification

```sh
node test/javascript/studio_spatial_math_test.cjs
node test/javascript/studio_spatial_browser_test.cjs
node test/javascript/studio_spatial_vision_test.cjs
```

Browser tests require Playwright/Chromium and FFmpeg/FFprobe. The browser fixture uses fake webcam capture and deterministic landmark messages, actual videos/WebGL/MediaRecorder and authenticated API fixtures. The separate vision test loads the real pinned WASM/models and a public MediaPipe portrait fixture. `test/javascript/prepare_spatial_fixtures.sh` prepares that cache and two short colored video clips. Local end-to-end fixtures validate the integration contract; they do not prove production WebRTC/Blender worker deployment or delivery to third-party platforms.

## Primary references

- MediaPipe Face Landmarker: https://developers.google.com/edge/mediapipe/solutions/vision/face_landmarker/web_js
- MediaPipe Image Segmenter: https://developers.google.com/edge/mediapipe/solutions/vision/image_segmenter/web_js
- Three.js matrix construction: https://threejs.org/docs/pages/Matrix4.html
- Three.js video textures: https://threejs.org/docs/pages/VideoTexture.html

- Blender Python threading guidance: https://docs.blender.org/api/5.0/info_gotchas_threading.html
