# CPU rendering across independent Lightek installations

This adds the first authenticated bridge from a client installation to Lightek's CPU render cluster. The client retains its own database, queue, files, payment and Studio operation. It sends a bounded procedural scene snapshot over HTTPS. Lightek renders a separate operation, and the client streams verified outputs into its original operation and existing media-library/edit handoff. The client does not receive central database, Redis, Docker or worker credentials. Customers do not install rendering software on their devices.

## Current production contract

The bridge currently accepts **paid final CPU economy movies** made from cubes, spheres, cylinders, planes, cameras and lights, with basic transforms, look-at targets, material colors/metallic/roughness/transmission and location/rotation animation keys. The snapshot must already resolve to the existing CPU economy dimensions/samples. The central service does not silently change the paid snapshot.

An early Rack boundary rejects API request bodies over 1 MiB before Rails parameter parsing, including streams without a content length. Limits: 512 KiB per manifest, 128 objects, 100 animation keys per object, frame numbers 1–2400, 1–60 fps and the existing CPU economy renderer limits. Results are MP4, editable `.blend` and optionally PNG, up to 64 MiB each. False bundle/GLB flags and inert storyboard/source-credit metadata can travel with the snapshot; bundled sources and GLB export are not enabled by them.

Native templates, imported assets, character rigs, audio sources, modifier/authoring commands, advanced camera controls, still-only output and custom rendering profiles are outside this first remote contract. The normal movie/shot quote path validates eligible remote economy snapshots **before** creating checkout, so unsupported production work does not buy a render that this bridge cannot execute. Previously paid unsupported snapshots fail explicitly and require an appropriately configured local worker or the later source-transfer path. Other Studio job families retain their existing routing.

This is procedural scene production, not neural text-to-video. It neither pools host RAM nor substitutes software for GPU hardware.

## Infrastructure deployment

1. Deploy this revision and run its migration on both the central installation and the independent client. Keep client remote routing off until both sides are ready.
2. Use the existing Gatekeeper-managed reservation federation connection for the client installation. Its server token is already in the client's Vault with the `LightekReservations::Federation::Client` policy. The bridge reuses that authenticated transport; it does not expose that token to the browser or broaden its Vault policy. The configured origin must be the intended central HTTPS origin. No response-supplied callback URL is used.
3. Centrally, set `STUDIO_CPU_REMOTE_PEERS` to an explicit comma-separated list of approved peer UUIDs. Default is empty, allowing no remote installations. Treat each grant as an infrastructure compute entitlement: a valid server-order identity alone does not grant compute. Keep central `STUDIO_CPU_REMOTE` unset. Configure the existing [dedicated CPU workers](shared-cpu-workers.md) and media runtime on central worker hosts.
4. On the client installation, set `STUDIO_CPU_REMOTE=1`. Economy operations handled by `ExecuteStudioOperationJob` stay on the client's ordinary `studio` queue for lightweight orchestration; remote pending/running states requeue a poll after 20 seconds. No local Blender process is started by that path. Keep the normal client job worker running. The client uses its own existing asset storage for results.
5. Verify the client's existing federation token authenticates, the peer is active and centrally granted, the Studio render capability is enabled, and normal local payment verification succeeds. Then quote and pay for a supported procedural **movie**, watch actual frame progress, and add the finished output to the edit through the existing handoff.

No client installation shares its database/Redis/filesystem with central Lightek. Central render hosts may still use the shared storage described in the worker-cluster guide. Central worker provisioning and enabling these settings remain operator deployment tasks, not side effects of merging the PR.

## Identity, payment and admission

The API authenticates the existing enabled peer and paid/provisioned server order, checks its central compute grant, and scopes every render/status/file/resume/cancel lookup to that peer. The JSON endpoint permits no local source paths, external asset URLs or executable authoring commands. Rendering retains the existing network-isolated media container and Gatekeeper render-capability check. Source-package upload is intentionally absent here.

The client checks its actual succeeded payment before remote dispatch, including retries. Central compute uses the approved peer entitlement; central does not fabricate or require another end-customer bank transaction, and does not claim to independently verify an external installation's customer payment. Configured pricing and the original checkout remain unchanged. No new charge is created by polling, retrying a response or resuming saved work.

A random persisted request key and canonical snapshot digest make submission idempotent. Reusing a key for different content is rejected. Polling does not enqueue another central render. A missing enqueue receipt can be retried; the enqueue marker is written after queue submission so the crash window permits duplicate delivery rather than lost work. Existing operation leases reject duplicate running/terminal deliveries.

Admission permits at most two pending/running renders and 100 retained render records per peer. Capacity backpressure returns HTTP 429; the client keeps its paid operation pending and retries after 20 seconds with the same request key, rather than sending it to another checkout. The existing per-site CPU lease cap applies to execution across central projects. These are bounded admission/concurrency limits, not strict FIFO fairness, wall-clock accounting or an unlimited storage entitlement. Retention cleanup/quotas beyond these bounds remain operator work.

## Transfer, failure and cancellation

Completed file receipts contain names, sizes and SHA-256 digests. Downloads use fixed, peer-authenticated HTTPS paths on the configured origin, stream in bounded chunks and stop above 64 MiB. CPU JSON calls have a 30-second overall deadline and individual file transfers have a 180-second overall deadline, in addition to connection/read timeouts. Redirects and server-provided download URLs are not followed. The client verifies size and digest before attachment and marks its operation complete only after the required files transfer. Retrying replaces the same artifact records, preserving media handoff identity.

A dropped first response retains the original request key. A failed local transfer retains the central operation and can retry through the existing **Resume saved frames · no new checkout** action. Explicit resume can recover a failed central attempt under the same key and snapshot. Resuming a local failure while central work is still pending/running attaches to that existing work. There is no automatic rerender loop.

Local polling forwards an observed cancellation to the peer-scoped central cancel endpoint. A lost connection can prevent immediate cancellation; already-running central work remains bounded by its existing render timeout and requires operator cancellation if the client cannot reconnect. The original billing/refund policy still applies. Central peer disablement or grant removal blocks further access and is checked during leased render heartbeats; an interrupted supervisor still needs the existing worker recovery process.

Within the central cluster, checkpoints use its existing shared worker directory. Checkpoints are not copied to the client and native sources are not uploaded. A crashed local supervisor is reconciled through the existing lease sweep/listing and can explicitly resume. Disabling the client flag stops new remote dispatches; operations with a persisted remote receipt continue on their original remote path. Receipts bind the configured origin/peer/credential reference, and a changed connection is rejected rather than silently submitting paid work elsewhere. Drain or reconcile in-flight work before changing that connection.

## Evidence and remaining scope

The focused integration harness exercises actual peer-token authentication and Rails HTTP actions, the actual JSON client and chunked-download code, admission/idempotency, payment checks, pre-checkout validation, lost-response reuse, cancellation and checksum rejection. A real native Blender/FFmpeg movie runs as a distinct central operation and returns to the original paid client operation without a central customer charge. The socket is substituted with a second Rails integration session; the harness shares a SQLite database and does not establish network/TLS or deployment behavior across two physical installations.

Production acceptance still needs independent databases, real HTTPS/Vault configuration, PostgreSQL contention, central container limits, host loss and a complete paid production-to-edit workflow. The integrated go/no-go remains a later sprint. Next implementation work is source-package transfer for native scenes, reusable characters/rigs and audio, followed by further quota/accounting and measured economical neural runtimes.
