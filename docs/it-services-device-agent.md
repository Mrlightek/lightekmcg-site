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

Keep `lightek_backup_restore.py`, `lightek_live_restore.py`, and
`lightek_native_patch.py` in the same directory as the device agent.
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
recovery, malware removal, MDM, and device installers require separate providers.

## Deploy one Debian-family package update

The APT deployment action upgrades one already-installed package to an exact
version selected by an operator, accepted by the device owner, and pinned by
the endpoint administrator. It is available on Debian-family Linux. Windows and macOS use their native update brokers below.

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

## Deploy a Windows Update

Use an exact Windows Update ID and revision in the lower-case form
`update-guid=revision`. The local administrator records the same value in
`%ProgramData%\Lightek\EndpointPatch\policy.txt`. Approval for this update
covers acceptance of its vendor license. In that directory install
`lightek_windows_patch.ps1` and configure the fixed `\LightekEndpointPatch`
on-demand scheduled task to run it as SYSTEM with Windows PowerShell
`-NoProfile -NonInteractive -File`. Use the site's normal script signing
policy and the Task Scheduler setting that disallows concurrent instances.

Grant the agent account read and execute rights on that task, modification
rights on `inbox`, and read-only access to `outbox`. Keep the script, policy,
task definition, `work` directory, and output writes under administrator
and SYSTEM control. Use dedicated directory ACLs with inheritance disabled
where required. The agent account stays unprivileged.

The broker starts one locally pinned software update through Windows Update
Agent and verifies the exact installed ID and revision. It declines updates
that require interactive input. When Windows reports a pending restart, the
operator completes the reboot under local maintenance policy and requests a
fresh exact-target check. The broker checks installed state before attempting
installation, so the follow-up can verify the target without installing it twice.

## Deploy an Apple software update

Install `lightek_macos_patch.py` as the administrator-owned executable
`/usr/local/libexec/lightek-macos-patch` with protected parent directories and
an Apple-provided Python 3 runtime. Authorize only that exact executable
without arguments in sudoers for the dedicated agent. The administrator sets
the root-owned, mode-0644 `/etc/lightek/endpoint-macos-patch-target` under a
root-owned, non-writable-by-others `/etc/lightek`.

The operator, device owner, and locally pinned policy use the same target
`catalog label|package receipt ID or macos-build|expected version or build`.
The broker selects one exact label from Apple Software Update, installs it,
and reads back the native receipt or OS build. A version mismatch leaves the
action unverified. Use a separately scheduled follow-up after an authorized
restart for a build that cannot be verified before restart. Apple silicon
devices need Apple's existing volume-owner or managed bootstrap-token update
authorization. The broker does not collect a volume-owner password or
initiate a reboot.

Windows and macOS actions must be claimed in the scheduled ten-minute window.
A claim extends reporting for up to two hours to accommodate installation.
Native operations started by the local OS can outlive their reporting window.

## Authorize a live ZIP restore and retain rollback

Live cutover uses a same-filesystem atomic directory exchange on supported
Linux and macOS filesystems. Use one dedicated data directory owned by the
agent account. Pause all application writers and close their open handles
before arming the endpoint. Resume writers after checking the restored files
and permissions. The new tree contains regular files readable by the service
owner. Restored symlinks, mount points, and Windows live cutover are outside
this mechanism.

Point `LIGHTEK_RECOVERY_CUTOVER_AUTHORIZATION` to a local owner-only JSON
file (mode 0600). An endpoint operator creates it after quiescing the
application, with these fields.

```json
{
  "operation": "cutover",
  "live_directory": "/srv/lightek/client-data",
  "sha256": "<approved ZIP SHA-256>",
  "expires_at": 0,
  "reference": null
}
```

Replace `expires_at` with a Unix timestamp up to 30 minutes in the future.
Set the existing `LIGHTEK_RECOVERY_ARCHIVE` and a private mode-0700 staging
directory on the same filesystem. The Lightek operator schedules **Cutover
backup restore** for that archive and the customer separately authorizes
replacing live files.

The agent consumes local authorization before activating staging, writes a
durable journal, validates the new live tree, and attempts an immediate
exchange back if readback fails. It retains the previous directory on success.
If execution is interrupted, examine the two directories and the retained
journal before resuming writers. The cutover reference identifies the journal
and retained prior tree.

For a later rollback, pause writers again. Re-arm the local JSON with
`"operation": "rollback"`, the issued staging reference in `reference`, the
same archive digest and exact live path, and a fresh deadline. As the dedicated
agent account, run `python3 scripts/lightek_live_restore.py SHA256 REFERENCE`.
It checks both directory identities from the durable journal before exchanging
them. The prior live directory returns to service, and the replaced recovery
tree is retained for inspection.
