# Spatial posts, communities and remixing

## Post contract

Every published post retains a normal, independently playable MP4/HLS rendition and poster. The optional immutable spatial manifest is content-addressed, versioned, and refers to authorized asset variants. Existing social/OTT publications remain usable without WebGL. TikTok/Roku and other flat destinations receive the rendered master; interactive stage metadata remains a Lightek capability unless a destination explicitly supports it.

Example manifest for the React prototype:

```json
{
  "version": 1,
  "coordinate_space": "Y_UP_METERS",
  "post_id": "post-42",
  "scene_revision": 18,
  "flat": {"url": "/api/lightek/pwa/posts/42/master", "fps": {"num": 30000, "den": 1001}},
  "window_width_m": 0.5,
  "view_bounds_m": {"x": 0.035, "y": 0.025, "z_min": 0.5, "z_max": 0.7},
  "rig": {"default_camera": "main", "cameras": [{"id": "main", "position": [0, 0, 0.6], "quaternion": [0, 0, 0, 1], "lens_mm": 50}]},
  "angles": [{"camera_id": "main", "start_frame": 0, "duration_frames": 300, "media_url": "/api/lightek/pwa/posts/42/main"}],
  "assets": [{"id": "prop", "url": "/api/lightek/pwa/assets/15/proxy", "sha256": "CONTENT_HASH", "position": [0, 0, -0.6], "quaternion": [0, 0, 0, 1], "scale": [1, 1, 1]}],
  "animation": {"tracks_url": "/api/lightek/pwa/posts/42/tracks", "timebase": "integer_frames"},
  "depth": null,
  "remix": {"allowed": true, "license": "creator-selected-license", "source_scene_id": "scene-9", "attribution": ["creator-id"]}
}
```

Production validation must reject unknown schema versions, excessive mesh/texture budgets, non-finite transforms and unauthorized asset URLs. Store canonical Blender Z-up transforms separately and convert explicitly to browser Y-up; do not reinterpret one matrix convention as another. Record camera rigs and bounded viewer offsets, rather than identifying raw face landmarks or perpetually replaying the creator's head motion. Animated transforms and camera cuts use the common integer-frame timebase. Depth descriptors need source frame/camera IDs, projection, encoding/range and synchronization policy; null means no server-depth occlusion.

## Viewer experience and prototype

`examples/spatial-editor/src/SpatialFeedPost.tsx` is a React container; pass `loadFeedStage` from `public/lightek/spatial/feed-stage.js` as its loader. It keeps the normal video visible, loads actual GLB stage geometry when at least 60% visible, bounds/smooths mouse or optional mobile orientation offsets, and unloads GPU resources offscreen. Mobile motion permission comes from a user gesture. Reduced-motion viewers keep normal video. No webcam is required for viewing. The loader rejects external/non-Lightek asset URLs; a production gateway must additionally enforce asset permissions, hashes and budgets.

The stage uses an off-axis physical-window frustum. It does not merely rotate the video rectangle or claim to reconstruct its missing backside. Multiple pre-rendered angles provide discrete viewpoints/crossfades. Continuous novel views need real lightweight geometry, a suitable reconstructed representation, or a requested server render. Feed viewers should not automatically allocate a persistent Blender worker per scroll item. A production feed-level scheduler should permit only the focused post to animate and budget adjacent prefetching; the prototype's per-post visibility threshold is not a global scheduler.

## Fork Scene protocol

`POST /spatial/scenes/:source/forks` is a proposed authenticated, idempotent endpoint accepting source immutable revision, request key, destination community and permitted identity substitutions. In one transaction: authorize source visibility AND remix rights; check licenses of every nested asset; create a creator-owned project/scene referencing immutable permitted assets; copy camera/timeline/light data; retain source lineage and attribution. Do not copy access tokens, private files, live webcam tracks, provider credentials, publication rights or purchased licenses that disallow redistribution.

Return the new scene ID/revision plus a remap of object IDs. The creator then attaches their own local webcam/avatar, edits cameras/lighting, previews, saves and explicitly republishes. Publishing revalidates current rights, produces a flat master and spatial manifest, and records derivative credits. Rights revocation, moderation and asset deletion must be enforced by the asset gateway and descendants policy, rather than silently broadening source visibility. Concurrent source changes do not alter the pinned fork.

## Community Asset Hub

Use existing StudioAsset ownership/site boundaries with immutable versions, hashes, original + optimized GLB variants, thumbnails/turntables, license/provenance, animation compatibility, rig schema and moderation state. A community grant permits discovery/use under that license; it does not transfer ownership. Render parsers in isolated workers with budgets. USD/GLTF with external dependencies must be packaged and validated before staging. Camera rigs and shader presets are declarative validated parameters. Do not execute arbitrary community JavaScript; arbitrary GLSL needs review, resource limits and a safe fallback.

Discovery should show an actual preview and a clear action: place asset into the current shot, apply a camera rig, or start a scene template. Always preserve originals and reveal processing failures; a list of empty controls is not a successful import.

## Distribution and creator economy

Object storage holds immutable manifests, masters, aligned angle segments, depth variants and mesh/texture LODs. Signed permission-aware URLs and cache keys isolate private/community content. CDN HLS/DASH or ordinary video delivers feeds; WebCodecs is an optional decoding/compositing capability and not a distribution protocol. Use WebRTC for live collaborative editing/interactive sessions with an SFU when fan-out is needed. Existing broadcast delivery can distribute a flattened composition. Keep full Blender source on the creator's instance unless explicitly licensed for transfer.

Use each customer's own deployment/resources and configurable local worker concurrency. Cache public immutable derivatives at the edge, prefetch only an adjacent post, stop hidden decoding, adapt resolution/LOD, and reserve live GPU renders for active editors or paid interactive sessions. Measure actual egress/render costs before setting prices.

Build purchases/subscriptions/tips on existing DymondBank/payment and community entitlement records: immutable license purchase receipt, creator/platform split, refunds/chargeback state, entitlement checks at download/fork/publish, and a ledger separate from asset ownership. Scene template tips do not silently buy remix rights. Subscription expiry follows the license terms for already published derivatives. These are proposed platform contracts; this PR's prototype does not create a live marketplace, fork API or billing product.
