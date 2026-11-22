# Primary production recovery

## Release acceptance

The production workflow records a release only after the host checkout matches the requested commit, Apache and the deployed Sidekiq consumer pass their checks, and the primary watchdog timer is active. It then polls the public release endpoint for that same Rails process revision. Service and timer evidence comes from the production deployment job.

## Recover a failed primary worker

The host-level `lightek-primary-worker-watchdog.timer` checks the primary Sidekiq unit even when the worker cannot process jobs. The deployed script takes the same checkout lock as a release and requires the last accepted checkout and matching local HTTPS release before starting a failed unit. Intentional stops are preserved. It tries once until it observes the unit running or a different release is accepted. Successful recovery requires the new process to register the Studio queue and local HTTPS to serve the same release.

Inspect the latest host result with `journalctl -u lightek-primary-worker-watchdog.service`. The exact successful marker is `GATEKEEPER_PRIMARY_WORKER_RECOVERED`. A missing registration or a failed service start leaves a failed systemd run for review.

## Replace the production database

The cutover tool operates on two databases on the same PostgreSQL instance. Use a trusted custom-format PostgreSQL backup with an approved recovery point, and retain it separately. Create an empty candidate database with the same owner as the live one. Run `inspect` for the cluster ID and both database OIDs, then run `prepare --archive <approved-dump> --confirm <candidate-name>` with those identifiers. The restore runs against the empty candidate as the shared database owner in one transaction. Verify application data, attachment references, private keys and external dependencies against that recovery point. Compare the queued jobs and recent writes against the candidate before reopening the worker.

Use a PostgreSQL maintenance connection with rights over both databases. The tool uses `psql` connection environment settings and connects to the `postgres` maintenance database for naming changes. Avoid passing credentials on the command line. A candidate and retained name must begin with the live database name followed by an underscore.

1. Run `primary_database_cutover.py verify` with the live, candidate and retained names. Record the live and candidate OIDs from its receipt. The retained name must be available.
2. Establish the maintenance window. Stop Apache, Sidekiq, Cable and other database clients. Pause application writers and external jobs against the affected database. Keep them stopped through the name switch.
3. Run `fence --phase original`, providing both OIDs and `--confirm` with the exact live database name. Next run `promote` with the same identifiers. Both databases remain fenced. Inspect the returned mapping before proceeding.
4. Run `open --phase replacement`. Bring up the web service and verify the release, database identity and application reads before resuming application writes and workers.
5. To reverse the names, fence the databases with `fence --phase replacement`, then run `reverse` and `open --phase original` with the original identifiers. Reconcile any writes since opening the replacement before deciding to reverse. Both database copies are retained.

Every subcommand takes `--live`, `--candidate` and `--retained`. Mutations take `--cluster-id`, `--original-oid`, `--replacement-oid` and `--confirm`. Preparation confirms the candidate name. Cutover mutations confirm the live name. `inspect` reads the current mapping and session counts after an interrupted client command. The CI rehearsal exercises these steps against disposable PostgreSQL databases.
