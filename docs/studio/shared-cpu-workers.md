# Shared CPU workers within a Lightek installation

CPU economy operations submitted through `ExecuteStudioOperationJob` can run on dedicated Lightek Sidekiq hosts. A creator saves, quotes, pays and resumes through the existing Studio flow. The worker reads the authorized snapshot and source attachments from the same installation and returns artifacts to that operation's media library. Creators do not install Blender, drivers or model packages on their devices.

This is a trusted worker cluster for **one Rails installation**. Each worker has that installation's database, Redis, Rails secrets and storage access. It is not an endpoint that accepts commands or asset URLs from another client installation. Do not share one installation's database credentials with an independent client installation.

## Operator deployment

Keep the default deployment unchanged until dedicated workers and shared storage are ready. The default queue remains `studio`; the new database leases also protect economy operations there. Apply the normal migration before restarting application and job processes.

For dedicated hosts, supply through Lightek's infrastructure deployment:

1. The same application revision, Ruby dependencies and configured Studio media runtime on each trusted host. Runtime containers continue to use CPU-only, network-isolated rendering with the existing memory/CPU limits. This change does not create or purchase a server.
2. The same installation's private database and Redis connections and required Rails secrets. Keep these on the managed private network; do not expose database/Redis ports to creators. Do not use an independent client's database or Redis namespace.
3. A shared POSIX filesystem mounted at the **same absolute application storage path**, including Active Storage's configured local root, `storage/blender_jobs` and operation locks. It must support working cross-host `flock` semantics and atomic rename. The application currently uses Disk Active Storage in production: independent local disks are not a shared asset store. Confirm a private source file uploaded through the web host can be read by each worker, and a result saved by a worker can be downloaded through the normal authorized web route. Blob storage alone does not share frame checkpoints or operation locks.
4. Set `STUDIO_CPU_DEDICATED_QUEUE=1` and `STUDIO_CPU_SHARED_STORAGE=1` on web and all job processes. The second variable is an operator acknowledgement, not an automated mount verification. Misconfigured routing fails explicitly instead of silently rendering on the ordinary worker.
5. Set `STUDIO_CPU_WORKER=1` **only on dedicated worker processes**, then start `bundle exec sidekiq -C config/sidekiq_cpu.yml`. This configuration consumes only `studio_cpu`, with one thread. Keep ordinary workers on their existing queue configuration. A regular worker receiving previously queued economy work redirects it to `studio_cpu` without rendering it. An enabled queue with no running dedicated consumer will remain pending.
6. Give every worker host a separate local `STUDIO_CPU_RENDER_LOCK_ROOT` (for example `/var/lib/lightek/studio-cpu-slots`), writable by the worker user. This coordinates renderer processes on that host. The shared operation locks remain under `BLENDER_OUTPUT_ROOT/.locks`. If local slot files are instead on the common storage mount, their limit applies across the entire cluster, reducing parallelism safely.

Start with one worker per host, one render slot per host and one active operation per tenant. A website is the tenant boundary; projects without a website use the project owner. `STUDIO_CPU_TENANT_SLOTS` allows 1–8 and must be consistent on all hosts. This is a concurrency cap, not a promise of strict FIFO fairness, time quotas or a billing discount. Different tenants can use different hosts concurrently; a single render still uses one host's CPU and memory.

Before adding a second host, verify operation-lock exclusion across the actual mount: hold a `.locks` test file with `flock` on one host and confirm a nonblocking lock on another fails until the first releases it. Drain `studio_cpu` before disabling routing or removing its consumers; changing the environment does not move jobs already in Redis.

The dedicated path currently covers economy operations executed by `ExecuteStudioOperationJob`, including its existing render/Nevaeh entry points. Separate native authoring-preview, asset-save, custom-profile, timeline, neural-generation and interactive-workstation jobs retain their existing routing. This is not a claim that every Studio task has moved off the application host.

## Ownership, interruption and recovery

Admission locks a database pool row, checks the tenant's unexpired leases and claims the operation under its row lock. A duplicate delivery cannot claim a running or terminal operation. Each accepted attempt gets a fresh random fencing token and a 90-second lease. Source download and render progress renew that lease; Blender's normal supervision checks ownership while the process runs. An expired lease cannot be renewed.

Progress updates, artifact attachment and completion verify current ownership. A worker whose token was replaced cannot overwrite a newer attempt's state or publish its outputs. The shared workspace lock additionally prevents a paused old process and a resumed attempt from writing the same checkpoint directory concurrently; the new attempt defers while that lock remains held. Stale or cancelled attempts are stopped by the existing media subprocess/container cleanup path when the supervisor resumes. A vanished supervisor can leave a container or remote filesystem lock requiring operator cleanup: database expiry does not itself kill another host's process.

The normal Sidekiq cron sweep checks expired leases every minute. Opening **Renders & handoffs** or choosing resume also reconciles only the authorized operation/project. Operators can run `bin/rails studio:cpu:reconcile` to sweep manually. A vanished attempt becomes failed with a recovery message; the sweep never starts a replacement render, performs checkout or creates a charge. If the job's ensure released an already-expired lease, it still remains eligible for reconciliation.

For a paid economy movie, use **Resume saved frames · no new checkout**. Existing site access, successful-payment and immutable-snapshot checks remain mandatory. A resumed job may land on another dedicated worker and use the common frame directory. Existing fingerprint/checksum validation decides which frames are reusable. All hosts need the same engine revision/runtime for reuse; a changed fingerprint safely rerenders instead. Successful or cancelled jobs retain existing cleanup behavior. Failed checkpoint retention still requires operational disk management.

## Verification and remaining work

Focused checks exercise queue opt-in, ordinary-worker redirection, per-tenant admission across projects, separate tenant admission, duplicate delivery, expiry and scoped reconciliation, paid resume without another transaction, stale-token publication rejection, workspace lock exclusion, failure/cancellation cleanup and a real CPU Blender movie/artifact handoff under a live lease. Existing CPU rendering/checkpoint tests are regression checked.

The local integration harness uses SQLite and native Blender. It does not establish PostgreSQL concurrency behavior under production load, cross-host filesystem locking, deployed Docker limits or worker-host failure recovery. Those remain required cluster acceptance checks in the integrated verification sprint. No production worker is provisioned or enabled by merging this change.

Authenticated federation between independent client installations and a central Lightek pool, byte-streamed source/checkpoint transfer without a shared filesystem, tenant compute accounting, strict scheduling fairness, automatic worker inventory/provisioning and economical neural-runtime benchmarks remain subsequent work.
