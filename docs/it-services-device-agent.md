# Lightek managed-device agent (Linux pilot)

This is an **opt-in, read-only reporting pilot**, not a remote control agent.
It samples Linux CPU (/proc/stat), memory (/proc/meminfo) and root filesystem
capacity. It does **not** scan for malware, verify backups, inspect patch state,
run remote commands, or prove compliance.

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

Run `python3 scripts/lightek_device_agent.py` on the enrolled Linux device.
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
back with a one-time nonce and recorded in the audit model.

**Not supported yet:** OS patch installation, malware removal, verified backup
restoration, macOS MDM, Windows MDM, device enrollment installers, and
production cross-platform validation. Those require OS-specific privilege
brokers and real customer consent/entitlement checks. No generic remote shell
is provided.
