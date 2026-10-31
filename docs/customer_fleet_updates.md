# Customer and service fleet updates

Dashboard → Operations → Customer Updates supports Rails installed directly on
server instances, CDN configuration, and specialized services. The main application
keeps its existing production deployment. Customer releases default to **native
Rails under Passenger**, with Docker used only for configured dependencies.

## Deployment adapters

| Adapter | Deployment behavior | Verification |
| --- | --- | --- |
| `native_rails` | Fetch exact Git SHA into the registered checkout; preserve environment files; back up PostgreSQL; install locked gems; migrate; compile assets; validate boot; restart this Passenger application and configured worker/cable services | Public HTTPS health, boot-captured running Rails revision, Git SHA, configured worker health |
| `cdn_nginx` | Fetch the CDN repository's exact SHA; optionally run its deploy hook; validate the actual Nginx configuration and prove the registered file is included; reload the configured Nginx service | Nginx validation, acknowledged reload, active service and public HTTPS health; optional revision probe/hook |
| `systemd_service` | Fetch the service repository's exact SHA; optionally run its build/deploy hook; restart or reload the named service | Active systemd unit, public HTTPS health, and a required running-revision endpoint or verification hook |
| `docker_compose` | For explicitly containerized installations only: pull a digest-pinned application image and use the established managed-site updater | Running web/worker image digests and public release health |

The native Rails adapter never builds/pulls an application container. Its Compose
commands only back up the configured database or control an explicitly configured
container worker. Existing DB, Redis, MinIO, storage, TLS and customer credentials
are preserved. Updates do not allocate replacement servers.

## One account, selected installations, or the fleet

Sync discovers existing `GatekeeperProject` records as native Rails installations.
Deployment defaults come from the actual project: checkout, application user, Ruby
version, hostname and worker service. Adjust the environment file, Ruby binary path
or worker mode in its Dashboard deployment profile when the server differs from
those defaults. Previously saved profiles are preserved on subsequent syncs.
Website metadata without a project does **not** imply a Docker application; it
requires an explicit adapter/profile before it can receive an update.

Register CDN and other services in Dashboard using their existing Gatekeeper node,
hostname, component, repository and deployment profile. Different components can
share a hostname, and CDN replicas on different nodes can share the same public
hostname/component. Assign the installation to its customer account when applicable.
Only super administrators can read or change fleet controls.

Select a release, then choose individual installations, all matching installations,
or one account's matching installations. Matching includes adapter, component,
repository, channel and release pin. A Rails application release cannot update a
CDN or unrelated service. The preview is a fixed target snapshot; start it after
reviewing the targets. Canaries, batch sizes (1–50), UTC scheduling, pause, cancel,
retry and automatic promotion work identically for every adapter.

For customer-specific development, register the custom commit as a separate
release and assign it in **Installation update policies → Assigned release**.
The pin protects the customer from both automatic updates and broad manual
rollouts of other releases. To replace the custom version, deliberately change or
remove the pin. An active rollout must be canceled before its profile/pin changes.
Tracked uncommitted work on native servers is refused rather than overwritten;
untracked environment/storage files are preserved. Unexpected checkout revisions
also stop an update for review.

## Native Rails profile

```json
{
  "app_root": "/var/www/customer-site",
  "app_user": "lightek",
  "env_file": "/etc/lightek/customer-site.env",
  "ruby_bin": "/home/lightek/.rbenv/versions/3.3.6/bin",
  "worker_mode": "systemd",
  "worker_service": "customer-site-sidekiq",
  "health_url": "https://customer.example.com/up",
  "revision_url": "https://customer.example.com/__lightek/release",
  "compose_file": "/var/www/customer-site/docker-compose.yml",
  "db_service": "db"
}
```

`worker_mode` can be `systemd`, `compose`, or `none`. In compose mode,
`worker_service` names the existing worker container service; it must already run
from the host's deployed code. `compose_project` can select a dependency project's
existing name. `cable_service` optionally names an existing native WebSocket unit.
Set `backup_strategy` to `hook` and provide an absolute `backup_hook` executable
when PostgreSQL is not in the configured Compose project. A backup hook writes a
checked SQL snapshot to stdout; the updater saves it into a protected backup file.

An optional `maintenance_hook` executable receives `enable`/`disable` for the
installation's existing per-site maintenance or load-balancer drain procedure.
The default native path follows the existing live Passenger deployment pattern;
it does not stop the shared Apache service or change other virtual hosts. Without
that hook, web requests can continue while migrations run, so online migrations
must be compatible with the previous code. Worker shutdown precedes the backup.

`/__lightek/release` reports the SHA captured once at Rails process boot. Reading
HEAD on each request would incorrectly claim a deployment succeeded while old
Passenger workers still served requests. The shared production deploy script also
explicitly restarts the Passenger application after deploying code.
Revision probes connect to this instance at `127.0.0.1` while preserving the real
TLS hostname and Host header. Set `probe_address` to another local IP if its HTTPS
listener uses a different address. Public health is checked separately, so a
load-balanced hostname cannot make another replica's revision stand in for this one.

## Nginx CDN profile

Use the CDN's actual Git repository and choose a separate component, such as
`cdn_edge`. Its repository must already be included by the server's Nginx setup.
This adapter updates that setup; it does not invent an origin, vhost or cache path.

```json
{
  "app_root": "/opt/lightek/cdn-config",
  "app_user": "lightek",
  "config_file": "/opt/lightek/cdn-config/nginx/edge.conf",
  "service_name": "nginx",
  "health_url": "https://cdn.example.com/health"
}
```

The config file must resolve inside the registered checkout and appear in
`nginx -T` output. Invalid configuration is rolled back before a new config is
reloaded. Cache objects are never purged or deleted by this adapter. If the CDN
repository builds software in addition to configuration, set `deploy_hook` to an
existing absolute executable implementing that build/install procedure.

## Specialized service profile

```json
{
  "app_root": "/opt/lightek/realtime",
  "app_user": "lightek",
  "env_file": "/etc/lightek/realtime.env",
  "service_name": "lightek-realtime",
  "service_action": "restart",
  "deploy_hook": "/opt/lightek/realtime/bin/deploy",
  "verify_hook": "/opt/lightek/realtime/bin/running-revision",
  "health_url": "https://realtime.example.com/health"
}
```

Hooks run as the registered application user with the existing environment file
and `LIGHTEK_TARGET_SHA`. The deploy hook implements that service's actual build
or installation steps. A verification hook must query the running service/artifact
and print its exact source SHA; simply echoing the requested SHA is insufficient.
A JSON `revision_url` returning `source_sha` can replace that hook. Service control
runs through systemd as root; supported actions are `restart` and `reload`.

## Release publishing and activation

Run migrations and restart web/Sidekiq after merging. The existing cron loader
loads `Gatekeeper::Fleet::SweepJob` every minute from `config/schedule.yml`.

After a successful Deploy Production workflow, Publish Customer Release registers
that exact Git SHA as a native Rails release. It does not require an application
image or GHCR credentials. Native servers retain their existing Git/private-gem
authentication. For CDN/custom repositories, register their exact commit and
matching adapter/component/repository in Dashboard or call the authenticated
release callback from their own CI. No main-application automatic rollout policy
is applied to those unrelated repositories.

Configure `GATEKEEPER_FLEET_RELEASE_URL` in GitHub Actions variables as
`https://lightekmcg.com/gatekeeper/callbacks/fleet_release`, and set the same dedicated
`GATEKEEPER_FLEET_RELEASE_TOKEN` in Actions secrets and the main application environment.
SSH uses the existing node key/agent or audited installation/bootstrap Vault access.
Remote root SSH is required for service control. No secrets belong in deployment
profile JSON, release records or source URLs.

For an explicitly containerized installation, manually dispatch the publish
workflow with `adapter=docker_compose`. Only that path builds/pushes a customer
image and requires existing private-dependency CI credentials and GHCR read access.
The optional `LIGHTEK_FLEET_REGISTRY_SECRET_SLUG` uses a Vault payload containing
`username` and `password`, consumer `Gatekeeper::Fleet::Transport`, purpose
`fleet_registry`. Credentials travel on stdin and never enter application images.

Enable an installation's **Automatic releases**, then set
`LIGHTEK_FLEET_AUTO_ROLLOUT=true` on the main application to start matching native
Rails canaries automatically. Default behavior holds at the canary for operator
promotion. `LIGHTEK_FLEET_AUTO_PROMOTE=true` continues batches automatically.
Automatic releases must match the main Gatekeeper project's recorded deployed SHA;
late callbacks cannot auto-downgrade the fleet. Overlapping automatic releases wait
for active reservations, and superseded drafts are canceled. Customer pins remain
in force. The main control-plane app is excluded from customer application rollouts;
other remote components on a production node can be managed independently.

## Recovery and verification

Native updates keep protected logs, database snapshots and receipts under
`/var/lib/lightek/fleet/CHECKOUT_HASH/fleet-TARGET-ATTEMPT.*`. Container updates keep
their established `/opt/lightek-sites/DOMAIN/backups` records. Backup retention and
capacity are operator managed. Successful receipts update the installation and its
associated project's deployed SHA. Failed operations use existing KB/support
escalation, and the sweep recovers lost enqueues or stale workers.
Ordinary project deployments and native fleet updates share the same per-checkout
lock, preventing concurrent modification through the two Dashboard workflows.

Before schema changes, a native Rails failure restores the previous source and
services. After migrations begin, automatic code restoration requires the release's
explicit backward-compatibility declaration. Specialized deploy hooks can also
mutate state, so automatic restoration after invoking those hooks requires that
same declaration. Database restoration is never automatic. To deploy an older
release, verify schema compatibility, adjust any pin, cancel overlapping work, and
create a rollout for that release. Host OS distribution upgrades/reboots remain
separate from application/CDN/service repository deployments.

```sh
ruby test/standalone/fleet_updates_test.rb
python3 -m unittest discover -s test/standalone -p 'fleet*_test.py'
```

Tests exercise actual fleet persistence/coordinator/jobs, release boundaries and
pins, a 1,000-customer snapshot, real temporary Git fetch/checkouts, and native/CDN/
service success and recovery paths. Rails commands, Passenger, Docker, systemd and
network health are simulated in isolated tests. They do not claim live deployment.
