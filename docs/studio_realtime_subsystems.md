# Advanced Blender-to-browser subsystems

This extends `studio_spatial_4d.md`. These are service designs and integration contracts, not a claim that a deployed 60 fps WebRTC/Blender service exists. The reusable asset-staging helper is implemented and tested in Blender; endpoint registration, coordinator and media sidecar remain future integrations.

## 1. Low-latency rendered scene streaming

### Existing Live Studio and the new interactive path

The current live path is **browser canvas → MediaRecorder WebM chunks (500 ms) → ActionCable WebSocket → FFmpeg → RTMP/RTMPS and/or HLS**. `public/lightek/live/studio.js` calls `recorder.start(500)`; `app/services/studio/live/encoder.rb` produces 24 fps output and two-second HLS segments. It is useful for broadcasting and audience playback. It is not WebRTC, and its chunk/segment buffering cannot provide sub-50 ms interactive feedback.

Keep that publication path. Add a separate preview path:

**persistent Blender viewport → bounded latest-frame handoff → hardware encoder + WebRTC sender sidecar → browser decoded frame → Three.js compositor**.

Rails/Gatekeeper owns session identity, durable commands, scene revisions and signaling authorization; it should not relay raw 60 fps image buffers through Rails requests or ActionCable. The sidecar handles SDP/ICE/STUN/TURN, RTCP congestion feedback and media transport. An SFU becomes useful when multiple clients view one render; it does not reduce Blender's render cost.

### Frame extraction

`GPUOffScreen.draw_view3d` is a viewport API: it needs a valid GPU context, `SpaceView3D`, region and view/projection matrices. Do not assume a plain `blender --background` process can use it as a drop-in framebuffer source. Use a dedicated GPU-backed Blender viewport process with a controlled display/context, or begin with the existing headless render API and measure its actual frame rate. Xvfb alone is not evidence of hardware GPU acceleration.

Run scene changes and GPU calls on Blender's main thread. Network and encoding run in separate processes. Load the .blend once, retain geometry/textures/shaders, and render the active camera at a fixed preview resolution. Start at 720p with one camera; retain scene complexity/quality adaptation. Multiple arbitrary cameras do not become free because they share a scene.

The first handoff can use a bounded shared-memory ring containing pixels plus sequence/revision/camera/time metadata. Keep at most the newest pending frame; consumers skip obsolete frames rather than accumulate latency. CPU readback/RGBA→NV12 conversion is a measurable copy cost. An optimized GPU path needs a tested native GL/EGL/CUDA/external-memory bridge and synchronization fences. A Blender GL texture ID is not a shareable cross-process resource by itself.

### Encoder and transport

Use GStreamer + hardware H.264 encoding for the performance-oriented deployment; aiortc is a useful Python protocol/proof path. Prefer supported low-delay encoder settings, no B-frame reordering, no lookahead and bounded queues. Negotiate a browser-supported H.264 profile or another mutually supported codec. Keep bitrate/resolution adaptive.

Illustrative CPU-frame GStreamer pipeline (not a complete signaling server):

```text
appsrc name=frames is-live=true format=time do-timestamp=false
  caps=video/x-raw,format=RGBA,width=1280,height=720,framerate=60/1
! queue max-size-buffers=1 max-size-bytes=0 max-size-time=0 leaky=downstream
! videoconvert
! video/x-raw,format=NV12
! nvh264enc zerolatency=true bframes=0 rc-lookahead=0 gop-size=60
! h264parse
! rtph264pay pt=96 config-interval=-1 aggregate-mode=zero-latency
! application/x-rtp,media=video,encoding-name=H264,clock-rate=90000,payload=96
! webrtcbin name=peer bundle-policy=max-bundle
```

The application supplies monotonically increasing presentation timestamps and 1/60-second buffer durations, wires `webrtcbin` negotiation/ICE callbacks and provides TURN credentials where needed. The installed GStreamer/NVIDIA versions and available elements must be checked on the actual server. This pipeline still copies CPU pixels; the optimized variant replaces readback/upload/conversion with a GPU-memory path supported by the deployed plugins.

A minimal aiortc frame-track pattern, deliberately separate from Blender:

```python
import asyncio
from fractions import Fraction
from aiortc import VideoStreamTrack
from av import VideoFrame

class LatestBlenderTrack(VideoStreamTrack):
    def __init__(self):
        super().__init__()
        self.frames = asyncio.Queue(maxsize=1)
        self.origin_ns = None
        self.last_pts = -1

    def offer(self, rgba_array, captured_ns):
        # Called by this sidecar loop with an owned RGBA snapshot, not a reused mutable IPC buffer.
        if self.frames.full():
            self.frames.get_nowait()
        self.frames.put_nowait((rgba_array, captured_ns))

    async def recv(self):
        pixels, captured_ns = await self.frames.get()
        if self.origin_ns is None:
            self.origin_ns = captured_ns
        frame = VideoFrame.from_ndarray(pixels, format='rgba')
        pts = (captured_ns - self.origin_ns) * 90000 // 1_000_000_000
        frame.pts = max(self.last_pts + 1, pts)
        frame.time_base = Fraction(1, 90000)
        self.last_pts = frame.pts
        return frame
```

This adapter needs peer/signaling/timeout/shutdown handling and an IPC reader before it is a server. Do not call aiortc's default 30 fps helper and label the result 60 fps. Do not assume its default encoder is hardware accelerated or zero-copy. Drop stale frames, retain timestamps, and validate the actual encoded/decoded frame rate.

### Performance objective and measurement

60 fps gives a 16.67 ms render interval. **Sub-50 ms is an objective for a specified GPU, scene, client and nearby network, not a universal property of WebRTC.** Measure render-start→display and command→display separately. The latter also includes input sampling, command transit, scene staging and render scheduling.

An initial median budget to test, not measured performance:

| Stage | Target allocation |
| --- | ---: |
| Scheduling / latest-frame handoff | 5 ms |
| GPU viewport rendering | 8 ms |
| Transfer / color conversion | 2 ms |
| Hardware encoding | 3 ms |
| One-way network | 5 ms |
| Jitter buffering | 5 ms |
| Decode | 3 ms |
| Display scheduling | 8 ms |
| Total | 39 ms |

A 60 Hz display alone can add up to one refresh interval; WAN distance, TURN relaying and jitter can exceed this envelope. Record median, p95 and p99, actual rendered/decoded fps, dropped frames, queue depth, RTCP RTT/jitter and displayed frame age. Use sender/receiver clock synchronization or RTCP/media timestamp associations; subtracting server monotonic time from browser `performance.now()` is invalid.

Local head-parallax reprojection keeps head motion responsive while a newer server frame is in transit. Its latency budget includes tracking/inference/smoothing. The current first browser slice deliberately caps inference near 10 Hz with smoothing; it is not evidence of sub-50 ms head-motion-to-photon performance. That path needs its own optimized sampling/pose prediction/measurement stage.

## 2. Hybrid depth and occlusion

### First practical layer model

For the current prototype, stage the webcam person's segmentation mask on a virtual plane or displaced mesh. Native GLB/Three.js geometry can then participate in normal local depth testing, so an opaque object can be nearer or farther than that plane. This is staged 2.5D occlusion. A segmentation mask says where a person is; it does not measure their hand/body depth.

For a server-rendered image, RGB alone is insufficient for depth comparison. Start with background/person/foreground layers where applicable. For general intersections, the backend provides a camera-aligned linear-depth pass (and alpha/matte as needed), paired with the color frame.

### Required frame contract

Each color/depth pair must identify:

- Stream epoch, session, scene revision, render frame ID and camera ID.
- Presentation/media timestamp association, resolution and crop/letterbox transform.
- View/projection matrices, matrix storage convention and camera near/far values.
- Depth units and encoding: e.g. positive forward camera-space depth in meters.
- Window-to-Blender transform and asset/person-layer placement.

Reproject the server color/depth and the staged webcam mesh into the **same compositing camera** before comparison. Using the same screen UV on unrelated webcam and Blender images is not registration. On head movement, RGB-depth reprojection can expose missing surfaces; fill with the last safe background or request a new view rather than invent hidden detail.

After registration, a basic composite is:

```glsl
vec3 stage = texture(blenderColor, uv).rgb;
vec3 actor = texture(webcamColor, uv).rgb;
float matte = texture(personMask, uv).r;
float zs = texture(blenderLinearDepth, uv).r; // positive camera-space meters
float zp = texture(personLinearDepth, uv).r; // staged mesh depth or measured/reconstructed depth
float actorInFront = float(zp + 0.005 < zs);
vec3 result = mix(stage, actor, matte * actorInFront);
```

This simple illustration needs invalid-depth/background handling, edge feathering and consistent linear color processing. The epsilon reduces z-fighting; tune it to depth precision and scene scale. For integration with other local 3D geometry, write the matched depth into the compositing framebuffer or render registered RGB-depth meshes. For a standard non-reversed OpenGL perspective projection, linear depth `z` maps to depth-buffer value:

```glsl
float depth01 = farPlane / (farPlane - nearPlane)
              - (farPlane * nearPlane) / ((farPlane - nearPlane) * z);
gl_FragDepth = clamp(depth01, 0.0, 1.0);
```

That formula is not valid unchanged for orthographic or reversed-depth projections. Use the actual camera convention. A mask-plane prototype cannot make a real hand accurately wrap around a virtual prop; that requires registered per-pixel geometry/depth or a suitable pose/depth model.

### Transport and synchronization

Ordinary H.264/WebRTC video does not carry an arbitrary float depth buffer or alpha automatically. Options include a separate depth/matte stream with documented quantization, lossless compressed depth messages for lower resolutions/rates, or server-rendered foreground/background layers. Do not send raw full-resolution float depth at 60 fps without accounting for bandwidth; even 640×360×16-bit depth at 60 fps is about 221 Mbit/s before overhead/compression.

Quantization, chroma subsampling and video compression can corrupt depth boundaries. Validate thin geometry and moving silhouettes. Pair metadata to decoded frame timestamps, discard mismatched pairs and keep the last coherent composite. Use bounded/deadline-aware message assembly if depth is chunked over a data channel; a late depth packet should not freeze the interactive media pipeline.

A composited movie can be exported as ordinary RGB video for social/OTT playback. Retain camera/depth/layer metadata separately for an interactive Lightek experience. Third-party flat-video players cannot perform new viewer-specific head tracking merely because the video was created in Lightek.

## 3. Automated asset ingestion / Text-to-Stage

The pipeline is:

**frontend prompt or asset placement → Nevaeh structured plan → Gatekeeper asset/job command → existing managed ingestion → main-thread Blender staging → persisted object mapping/revision → updated preview**.

The generative model produces a typed plan (asset kind, existing library asset IDs, staging intent, placement, materials, animation choices). Asset-generation providers are jobs with progress/results; a text prompt is not yet a ready 3D model. Generated and uploaded files enter the same managed asset pipeline. OBJ/USD normalization and provider registration are explicit additions where the existing importer does not support them; the current browser's upload UI does not magically gain those formats from a Python example.

Example frontend intent:

```json
{
  "op": "asset.stage",
  "command_id": "uuid",
  "base_revision": 82,
  "params": {
    "asset_id": 901,
    "camera_id": 3,
    "screen": [0.2, -0.1],
    "distance_m": 6,
    "fit_fraction": 0.6,
    "default_color": [0.25, 0.55, 0.8, 1]
  }
}
```

The coordinator resolves a prepared local asset path and camera name from those IDs, then supplies that command over IPC. Keep file/network watching outside Blender. On Blender's main thread, call the implemented helper:

```python
from spatial_asset_staging import stage_asset

result = stage_asset(
    prepared_local_path,
    camera_name=resolved_camera_name,
    screen_x=0.2, screen_y=-0.1,
    distance=6, fit_fraction=0.6,
    color=(0.25, 0.55, 0.8, 1),
    name='Generated environment prop',
)
# Persist returned object mapping under stable Studio IDs, advance scene revision,
# acknowledge the command, then request the new camera preview.
```

`blender/spatial_asset_staging.py` imports GLTF/GLB or OBJ, preserves source parenting/materials, adds defaults to unmaterialed meshes, groups the new objects, computes evaluated bounds, fits them into the active camera frame (including lens shift), positions them at the requested normalized screen coordinate/distance, restores the original active camera and rolls back new objects on failure. It supports perspective and orthographic staging cameras. It is a tested reusable helper, not a deployed file-watcher/API endpoint.

Test with:

```sh
blender --background --factory-startup --disable-autoexec --python-exit-code 1 \
  --python test/operations/spatial_asset_staging_blender.py
```

Prepare `/tmp/native-viewport-proof.glb` using the existing fixture step first. Acceptance covers perspective/orthographic/lens-shift framing, invalid parameters and preserving the active camera. Next tests should include animated rigs, evaluated deformation/instances, complex materials and real generated assets before promoting this helper into the production ingestion capability.

## Delivery sequence

1. Keep the current broadcast path working; complete the canonical command→changed Blender frame loop.
2. Add a persistent GPU-backed viewport worker and latest-frame IPC; benchmark single-camera scene complexity at 60 fps.
3. Prove WebRTC with aiortc or GStreamer on one browser, then measure/optimize the GPU/hardware-encoder path.
4. Add coherent camera/frame metadata and registered matte/layer occlusion; then depth transport and reprojection.
5. Register the staging helper behind the existing asset/job capabilities; connect AI provider jobs and persist scene/object receipts.
6. Export or publish finished composites through the existing timeline/library/live pathways; certify actual destinations separately.

## Primary references

- Blender offscreen drawing: https://docs.blender.org/api/5.2/gpu.types.html
- Blender main-thread/Python constraints: https://docs.blender.org/api/5.0/info_gotchas_threading.html
- GStreamer NVIDIA H.264 encoder: https://gstreamer.freedesktop.org/documentation/nvcodec/nvh264enc.html
- GStreamer WebRTC transport: https://gstreamer.freedesktop.org/documentation/webrtc/
- aiortc media tracks: https://aiortc.readthedocs.io/en/latest/api.html
