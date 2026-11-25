# Same-host production blue-green rehearsal

This procedure stages a second Rails and Action Cable process on the current Linode and switches an Apache vhost between two immutable checkouts. The previous web processes stay available during the observation window. A rejected candidate leaves the active site serving traffic. The worker changes slots under an exclusive lock, with time for the previous Sidekiq process to drain. Jobs can remain queued during that handoff.

## Check capacity

Run the read-only report on the target host with a proposed budget for the complete inactive slot. Include Rails, Cable and Sidekiq in that budget even though Sidekiq will start only at promotion. Set a reserve for Apache, PostgreSQL, Redis, mail and workload peaks based on observations under representative load. Choose a storage path on the release filesystem.

```sh
python3 lib/scripts/gatekeeper/blue_green.py capacity \
  --inactive-mib 1024 --reserve-mib 512 --storage-path /var/www
```

The example numbers are inputs to the report. Capture peak startup memory and disk use in the rehearsal before deciding production limits. The preparation command refuses to start if available RAM is below the budget plus reserve. It bounds the inactive slot with a cgroup limit and counts no swap toward that budget.

## Install and rehearse on a disposable control plane

- Install the templates in `lib/scripts/gatekeeper/blue_green_units/` into the corresponding systemd unit and tmpfiles directories. Install `run_production_slot.sh` at `/usr/local/lib/lightek/run_production_slot.sh` as a root-owned executable, reload systemd, and apply the worker lock tmpfiles entry. The units use the existing app user, Ruby version, and environment file.
- Prepare exact-SHA Git checkouts at `/var/www/lightekmcg-slots/blue` and `/var/www/lightekmcg-slots/green`. Install locked gems and compile each release's assets before starting it. Keep each slot's runtime and PID files separate. Apply the established configuration and key wiring to both. Local Active Storage must point at the same backed-up storage. Ensure previously served fingerprinted assets are available during the overlap or cutover can break pages already open in a browser.
- Bring the existing verified revision up as blue. Use loopback web/Cable ports 28100/28101 for blue and 28200/28201 for green. Replace the primary HTTPS vhost's Rails and Cable routing with a single include at `/var/lib/lightek/blue-green/active.conf`. Keep the existing TLS, HTTPS redirects and unrelated vhosts. Generate the initial include using `blue_green.route("blue", verified_sha)` from the checked-in script. Create the directory and include as root under the approved initial cutover procedure. Validate Apache configuration and the public revision through the edge.
- Move Sidekiq to blue during the initial bootstrap. The legacy worker and its recovery timer must be disabled before the slot worker starts. The original workflow refuses future in-place primary deployment once the managed include exists. Enable the web and Cable slot services needed at reboot and enable `lightek-production-active-worker.service` to start the worker for the recorded slot. Leave both worker templates disabled directly. An interrupted cutover is held for recovery. Keep the former services available for a separately rehearsed bootstrap rollback.

## Prepare and switch

Commands below assume the managed vhost is already serving blue, both checkouts are immutable, and no legacy deploy or slot modification is running. Substitute actual full SHAs and verified budgets. Preparation and switching serialize on the same root-owned lock.

```sh
sudo python3 lib/scripts/gatekeeper/blue_green.py prepare \
  --slot green --sha "$GREEN_SHA" --inactive-mib "$BUDGET" --reserve-mib "$RESERVE"
sudo python3 lib/scripts/gatekeeper/blue_green.py switch \
  --slot green --sha "$GREEN_SHA" --expected-active "$BLUE_SHA"
```

Preparation starts only inactive web and Cable. The switch checks both revisions, the live TLS edge and the worker, then gracefully reloads Apache and verifies the new route. HTTP and Cable have separate probes. A failed switch restores the previous include and worker. After an interrupted switch, `recover` uses the stored rollback journal. To switch back after a completed cutover, use `switch` with the old slot and reverse the two SHAs. Leave old web and Cable processes running for the rollback window and until in-flight connections have drained.

This implementation refuses migration and schema changes and leaves database state alone. A later migration rollout needs a separately verified compatibility path for both application revisions and any queued job payloads. Rehearse failed inactive boot, worker failure, failed route verification and switchback against a synthetic control plane. Before enabling push-to-main automation, verify live capacity, bootstrap the primary vhost and worker safely, and wire reviewed immutable artifact preparation and Gatekeeper authorization into the deployment workflow.
