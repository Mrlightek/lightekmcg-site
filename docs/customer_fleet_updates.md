# Customer software updates

Dashboard → Operations → Customer Updates manages releases and customer server
rollouts. Main production continues to use its existing deployment workflow.
This pipeline updates the application and its container dependencies on existing
managed customer installations; it does not allocate or replace VPS instances.

## Release path

1. Merge the feature/bug fix into `main`. The existing Deploy Production workflow
   deploys the main application.
2. On successful production deployment, Publish Customer Release checks out that
   exact commit. It uses the website installer's existing delivery adapters and
   private-gem vendoring to build one `linux/amd64` image. Customer machines do not
   compile Rails or need access to the private gem repositories.
3. The workflow publishes to `ghcr.io/mrlightek/lightekmcg-site/customer` and registers
   an immutable release using the image digest, complete source SHA, and channel.
   Images include an OCI revision label which the updater checks before changing
   the running application. A manually dispatched build can choose beta and declare
   whether previous code remains compatible with its database migrations.
4. Select installations (or all eligible installations on the release channel),
   canary size, batch size (1–50), UTC start time and promotion policy in Dashboard.
   Preview the snapshot and start. Default canary size is one; default batch is ten.
5. Once a canary passes, promote it. Automatic promotion is an explicit option.
   A failed update pauses new work. Pause/cancel let in-flight updates finish.
   Retry keeps successful targets and retries failed targets, then continues.

## First setup

Run `bin/rails db:migrate` and restart the web and Sidekiq processes. The existing
Sidekiq Cron loader reads `gatekeeper_fleet_recovery` from `config/schedule.yml`.
The standalone recovery task can also be invoked with:

```ruby
Gatekeeper::Fleet::SweepJob.perform_later
```

Click **Sync registered installations** to discover previously installed customer
sites. Future successful `WebsiteDeployment` installations register automatically.
Discovery reads `GatekeeperNode.metadata.website_deployments` and legacy
`website_deployment.url` receipts. Local/control-plane/decommissioned nodes are
excluded. Existing opt-in and channel policies are preserved on subsequent syncs.
Only super administrators can read or change fleet controls.

Configure the following before the first release:

| Location | Name | Value |
| --- | --- | --- |
| GitHub Actions variable | `GATEKEEPER_FLEET_RELEASE_URL` | `https://lightekmcg.com/gatekeeper/callbacks/fleet_release` |
| GitHub Actions secret and main application environment | `GATEKEEPER_FLEET_RELEASE_TOKEN` | The same dedicated random bearer token on both sides |
| GitHub Actions | `LIGHTEK_CI_APP_ID`, `LIGHTEK_CI_APP_PRIVATE_KEY` | Existing CI GitHub App credentials for private dependencies |
| Main application environment, optional | `LIGHTEK_FLEET_REGISTRY_SECRET_SLUG` | Vault slug containing the private GHCR read credential described below |

GHCR images include private application/gem source. Keep the package private and
grant the publishing repository Actions write access. Customer pulls need read
access. Store a Vault secret containing `username` and `password` (a GHCR
read-packages credential) with consumer `Gatekeeper::Fleet::Transport` and purpose
`fleet_registry`, then set its slug above. Alternatively, configure GHCR read
authentication directly on each managed server. Passwords are sent on stdin to an
ephemeral Docker config and are not written into application environment files,
operation records, images or release receipts.

SSH uses the existing node key path, installation's Vault SSH credentials, or
the node's bootstrap credential. Existing install-time Vault policies continue to
apply through the `Gatekeeper::WebsiteDeployment` consumer and `website_deploy` /
`node_bootstrap` purposes. Remote root SSH is required for Docker and the existing
installer locks. A keyless standalone registration must have usable agent/default
SSH authentication or an explicitly configured node credential before updating.

## Optional automation

Set an installation's **Automatic releases** policy and channel in Dashboard.
Set `LIGHTEK_FLEET_AUTO_ROLLOUT=true` on the main application to start a one-server
canary automatically when the release callback arrives. The default still holds
at the canary for operator promotion. Set `LIGHTEK_FLEET_AUTO_PROMOTE=true` to
continue batches automatically after health checks pass.

Automatic rollout only runs when the release source SHA equals the main
`lightekmcg-site` Gatekeeper project's recorded deployed SHA. The existing production
deployment callback must therefore be configured and reporting successfully.
This check prevents late/replayed old build callbacks from auto-downgrading the
fleet. Callback retries cannot edit a published artifact or duplicate a rollout.
If an earlier rollout still owns a customer installation, the newer automatic
rollout remains a draft and the recurring sweep starts it when available. Drafts
superseded by a different main deployed revision are canceled automatically.
Overlapping rollouts cannot reserve the same installation, including paused and
failed targets. Cancel an earlier rollout before targeting its installations again.

## Installation transaction and recovery

The remote updater validates the managed site's hostname, project and environment,
takes the installer's hostname lock, pulls the digest and checks its source label.
It preserves the original Compose file, persistent database/storage volumes, ports,
TLS, owner account, site content and secrets. A small persistent Compose override
selects the pinned image for web and worker.

The updater stops web/worker writes, takes a checked `pg_dump`, runs migrations and
asset compilation, then restarts both services. This involves a brief maintenance
interruption per installation. Public HTTPS must report the exact new revision
and hostname, and both web and worker must run the requested digest before the
control plane records success. Database backups, protected
logs and JSON receipts live in `/opt/lightek-sites/DOMAIN/backups/fleet-TARGET-ATTEMPT.*`.
The operator must manage backup retention and free disk space.

Before migrations begin, failures restore previous image/environment settings.
After migrations begin, previous code is restored automatically only for a release
explicitly declared backward compatible. Otherwise recovery is manual and the
rollout pauses. Never automatically restore customer databases: a restore can
discard subsequent writes. To deploy an older application image, cancel active
work, verify schema compatibility, and create a new rollout using that older
release. Existing release records remain available for this purpose.

Repeated delivery skips an already verified revision+digest. Workers claim queued
targets transactionally, and a unique partial database index protects active
installation reservations. A recurring sweep recovers missed enqueues and pauses
workers that have stopped reporting for an hour. The remote command has its own
30-minute deadline, and the hostname lock protects retries against a still-running
remote process. Hard failures leave the protected remote receipt and backup for
inspection; failed operations also use the existing KB/support escalation service.

Host OS upgrades/reboots are separate from application releases. Image rebuilds
refresh container packages; this workflow does not run unattended `apt upgrade` on
customer hosts.

## Validation

```sh
ruby test/standalone/fleet_updates_test.rb
python3 -m unittest discover -s test/standalone -p 'fleet*_test.py'
```

These tests exercise the actual models, coordinator and jobs with an isolated SQL
database, including a 1,000-installation snapshot. Python tests run the actual
updater against temporary installation files and simulated Docker subprocesses,
covering successful updates, exact-image retries, ownership/provenance rejection,
private-registry handling, backup failure and compatible/incompatible recovery.
They do not claim a live GHCR publish, SSH deployment or full application boot.
Customer Update Acceptance runs this suite independently of ecosystem CI failures.
