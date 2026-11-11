# Understand results and recover blocked work

## Read the state precisely

- Queued: a job was accepted.
- Dispatched: handed to a downstream worker.
- Prepared: a watcher produced a plan; it has not applied it.
- Completed: the operation finished; inspect the output and exit status.
- Verified: a structured ticket's registered acceptance checks passed.
- Blocked/failed: inspect the saved error before submitting anything again.
- Evidence unavailable: the downstream record is missing; submission alone is not proof of success.

## Common fixes

**Unrecognized capability:** use /capabilities and /describe. A capability-shaped typo will not search unrelated documentation.

**Missing fields:** inspect the schema and replace sample IDs/filenames with accessible records. Input hints are not a complete schema when the reference says schema_needed.

**Permission denied:** select the correct application/site and account. Agents cannot grant their owner additional permissions.

**Stale edit:** read the record again and use its current lock_version.

**Worker paused:** inspect its last failed/blocked run. Fix the cause before enabling the worker. Pausing does not undo previously submitted work.

**Watcher paused:** inspect /watch show ID. Correct its target/access/network issue, then /watch resume ID. Edits to its detection rule establish a new baseline.

**No change detected:** the first poll only baselines. The next poll must observe a real matching change. New and updated are different conditions.

**Package helper unavailable:** deploy through the native setup/update pipeline. The runtime must be an Ubuntu host with the installed helper and correct app-user rule.

**Application output failed:** inspect stdout/stderr and exit_code. Check the adapter's typed inputs, installed binary, workspace input and output filename. Package/file effects are not undone by database rollback.

## Escalate with evidence

Open a ticket containing the action/event/run ID, intended result, actual status/error and reproduction command with credentials removed. Include the relevant capability's schema/documentation gap. This is more useful than a screenshot of a queued message alone.
