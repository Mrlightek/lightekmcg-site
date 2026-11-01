# Connected Studio workflows

## Replicated runtime

Native ordinary deploy, native fleet updates and paid-instance packaging invoke the same root installer: `lib/scripts/setup_studio_spatial.py`. It installs the Python environment, preserves per-installation secrets across runs, registers a systemd sidecar, adds WebSocket routing to matching Apache vhosts and configures a managed coturn relay with expiring credentials. Existing unrelated TURN configurations are not overwritten. Rails reads the private runtime configuration file, so customers do not copy secrets between Rails and Python environments.

The paid-instance packager now ships Blender, Python services and the dependency Docker context. Its native remote runner installs Rails/Passenger on the host and starts only Postgres/Redis in Compose. It preserves customer storage and private gem sources, pins a public source revision, and returns a native fleet profile. The known installer boot/routes overlays are fingerprinted and restored/reapplied during fleet updates; unexpected edits are refused. This path has syntax/contract tests; a fresh production VPS install has not been executed in this workspace.

CPU-only instances start with a usable Cycles render fallback, not a fabricated GPU capability. A GPU-enabled deployment profile retains its backend, display/authentication and encoder configuration. GPU drivers/display availability, GPU capture and actual internet latency require validation on that hardware. TURN opens 3478 TCP/UDP and the managed relay range 49160–49200 UDP when UFW is enabled; external provider firewalls must allow those ports too.

## Generate and stage

1. Site administrator: Dashboard → Studio & broadcasting → AI asset generation → save Tripo API key. It is stored in Vault with a restricted consumer/purpose.
2. Creator: Studio → Spatial / 4D → describe an asset → Generate & stage. The button explicitly invokes the configured provider and its charges.
3. An authenticated, idempotent request creates a durable Library asset/job. The Studio queue submits/polls Tripo, records the task ID, validates/downloads a self-contained GLB, preserves the original, optimizes static geometry/textures, and uses the existing asset ingestor to create its proxy/native preview metadata.
4. Blender fits the asset into the current camera frustum. The scene receives a persisted asset reference and transform with rig/collision anchors. These are anchors, not automatic skinning or physics simulation. The browser adds the actual model to the visible stage; an open Blender stream reconnects using the updated scene.
5. Progress and errors appear in Studio. Resume retries a known provider task or saved original; uncertain submissions are not automatically charged again. Processing continues when the tab closes, and the tab remembers its active job for status recovery. Provider keys are never returned to the browser.

Generation integration tests replace the external provider/download with a fixture but execute actual Blender optimization, asset ingestion and camera placement. No paid provider call was made during verification.

## Publish, explore and remix

The existing publication forms now offer **Include current interactive scene**, a rights confirmation and **Allow Fork Scene and asset reuse under CC-BY-4.0**, plus an optional community slug. Ordinary video/OTT delivery remains available. Spatial publishing stores an immutable scene snapshot and attaches immutable proxy blobs; later Studio edits do not rewrite the published stage. Fork-enabled posts also retain the permitted source blobs. Known incompatible source licenses reject automatic remix sharing.

Community posts expose **Explore 3D scene** and optional **Fork Scene**. The viewer loads real primitive/native GLB stage geometry through post-authorized URLs, provides bounded pointer/mobile-motion parallax and releases GPU resources offscreen. Only one opened feed stage is active at a time. The flat video remains independently playable. This is a published stage viewer; Blender simulations and full movie playback are not re-executed in the browser, and geometry cannot be reconstructed from flat video.

Fork Scene creates an owned project, scene, copied asset grants and camera IDs, preserving source attribution. The viewer's webcam is never inherited. Post visibility controls both metadata and asset delivery. Private-community asset derivatives cannot be republished outside their source community. Source grants remain attached to the immutable publication rather than opening the author's private asset API.

Library → Community Asset Hub accepts an accessible community slug, lists its remix-enabled spatial assets, and imports a selected asset into the creator's own Library. The existing preview/place/edit controls then apply. Imports and scene forks have stable request receipts. This does not implement an asset marketplace or monetary tipping system.
