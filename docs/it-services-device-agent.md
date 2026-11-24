# Lightek managed-device agent

The agent provides opt-in device monitoring, approved maintenance checks, and
backup sample recovery verification. Keep it under a dedicated local account
with read access to the data necessary for its configured checks.

## Prerequisites

An administrator must register the device in the Lightek network management UI,
assign its correct customer owner, issue a device enrollment token, and enroll it
through the existing Gatekeeper `device_enroll` action. The token must be kept
private. The agent requires Python 3 and direct access to the HTTPS Gatekeeper endpoint.
Configure the final endpoint URL because the agent rejects HTTP redirects.

## One-time report

Set the following environment variables in a restricted service environment,
not in a shared shell history or a public file:

- `LIGHTEK_DEVICE_URL=https://your-lightek-host/gatekeeper/device`
- `LIGHTEK_DEVICE_IDENTIFIER` — the registered device identifier
- `LIGHTEK_DEVICE_TOKEN` — the private device enrollment token

Keep `lightek_backup_restore.py` in the same directory as the device agent.
Run `python3 scripts/lightek_device_agent.py` on the enrolled device. On
Windows, use `py -3 scripts/lightek_device_agent.py`.
Schedule it with the device's local service manager only after confirming
customer authorization and a secure secrets store. The server heartbeat
timeout is five minutes; a reporting interval shorter than that is necessary
for continuously observed connectivity. Do not deploy to customer devices
without an agreed managed-service scope.

The Gatekeeper heartbeat authenticates the device token and stores validated,
bounded metrics. The endpoint accepts only its predefined telemetry fields.
The server must be migrated before sending telemetry. Token rotation revokes
the prior token. This is not a guarantee of integrity on a compromised endpoint.

## Tests

Run `python3 -m unittest scripts/test_lightek_device_agent.py` on Linux.
Run Rails tests and end-to-end device enrollment/heartbeat checks before release.

## Cross-platform status and read-only checks

The Python standard-library agent now runs on Linux, macOS, and Windows.
It reports root filesystem capacity on all three, Linux CPU/memory metrics,
and Windows memory load. macOS CPU/memory and Windows CPU remain unavailable
until verified native adapters are integrated; the agent does not fabricate
measurements.

After an authenticated heartbeat, an opted-in managed device can receive up
to ten time-limited operator-approved checks. It supports inventory inspection
and explicitly reports `unavailable` for patch, backup and endpoint-protection
checks without a configured trustworthy platform provider. Results are posted
back with a one-time nonce and recorded in the audit model. An operator can
approve a check for immediate delivery or choose a start time up to 30 days
ahead. Gatekeeper offers it during the ten-minute window following its
start time. Operators and the device owner can cancel pending checks and
review the result in their respective Dashboards. Disabling monitoring
cancels pending checks and clears retained telemetry. Cancellation prevents
future delivery and report acceptance. A read-only probe that already started
on the device may finish locally.

The patch inventory check counts available software updates from the locally
cached Windows Update catalog, Apple Software Update, or the locally cached
APT catalog on Debian-family Linux. The count reflects the catalog available
to the agent at check time. Use the operating system's management tools to
confirm update requirements and catalog freshness.

## Backup sample recovery

1. Put a non-sensitive, nonempty sample of at most 64 KiB in the configured
   backup with the root-level member name `lightek-recovery-canary.bin`.
   Record its SHA-256 from the original trusted bytes before making the backup.
2. Make that ZIP backup available to the agent at a locally configured absolute
   path in `LIGHTEK_RECOVERY_ARCHIVE`. Use a dedicated archive up to 16 MiB
   with a stored or deflated member. Grant the agent only read access.
3. In the operator Dashboard, schedule **Verify backup recovery** and enter the
   expected SHA-256. The device owner authorizes the scheduled test in their IT
   support history. Each test requires separate consent.
4. Gatekeeper issues the approved action during its window and accepts one
   claim. The endpoint restores the configured member into memory and reports
   its measured digest. Gatekeeper compares the digest with the operator's
   reference and records **Verified**, **Mismatch**, or **Unavailable**.

A verified result covers the configured sample from that archive. Full-system
recovery, live data restoration, macOS or Windows patch deployment, malware removal, MDM,
and device installers require additional providers and validation.

## Deploy one Debian-family package update

The APT deployment action upgrades one already-installed package to an exact
version selected by an operator, accepted by the device owner, and pinned by
the endpoint administrator. It is available on Debian-family Linux. Windows
and macOS currently provide patch inventory.

1. Install `scripts/lightek_apt_patch.py` as the executable
   `/usr/local/libexec/lightek-apt-patch`, owned by root with mode `0755` in a
   root-controlled directory. Create root-owned `/etc/lightek` with mode
   `0755`, then write one `package=version` line to the root-owned
   `/etc/lightek/endpoint-patch-target` with mode `0644`.
2. Use `visudo` to allow the dedicated, unprivileged agent account to run
   that exact executable without arguments. For an account named
   `lightek-agent` the rule is
   `lightek-agent ALL=(root) NOPASSWD: /usr/local/libexec/lightek-apt-patch ""`.
   Keep standard APT signature verification enabled and use trusted repositories.
3. An operator schedules **Deploy APT patch** with the matching exact
   `package=version`. The customer authorizes that version in their maintenance
   history. The agent claims the action once within the approved window.
4. The broker checks the local policy and simulates the upgrade. It downloads
   the exact package using APT, checks the archive identity, installs it, and
   re-queries dpkg. The Dashboard shows a verified result only when the
   authenticated endpoint reports the approved installed version.

A failed, interrupted, or expired action requires inspection of the native
package database before retrying. The agent does not request a reboot or a
downgrade. A package may ship maintainer scripts or restart its own services.
Cancelling monitoring prevents further authorization and reporting. A package
installation that has already started runs to completion locally.

## Restore backup files to a staging directory

Support staff can schedule **Stage backup restore** for a particular ZIP
archive by entering its SHA-256. The customer authorizes the specific archive
in the Dashboard. The endpoint administrator configures the absolute path to
that ZIP using `LIGHTEK_RECOVERY_ARCHIVE` and an access-controlled, writable
staging directory using `LIGHTEK_RECOVERY_STAGING`.

The agent verifies the archive digest, restores regular files into a fresh
private directory and reads back every file. Gatekeeper records the archive
digest, restored file count, total bytes, and local staging reference. File
contents stay on the device. Operators can use that reference to locate the
staged snapshot and validate it before a separate cutover. The workflow has no
live-file overwrite or unattended cutover. It supports ZIP archives up to
256 MiB, with up to 1,024 entries and 512 MiB of uncompressed files. It accepts
portable relative paths, excludes links, and does not reapply archive ownership
or permissions.

Fleet review escalates failed or unconfirmed deployments and staged restores
to Nevaeh's technical queue. Verification of the exact package version or
archive can clear that operation's finding once the endpoint reports a fresh
heartbeat. A single package result does not clear a fleet patch inventory
finding. Nevaeh's runbook can recommend a follow-up, which still requires
operator approval and a new customer authorization.
