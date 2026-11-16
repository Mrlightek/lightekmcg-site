# LightekMCG agent execution rules

## 1. Page-to-worker mapping

- Maintain an explicit registry mapping each documentation page's repository-relative path to exactly one stable page-worker identity.
- Bind each page-worker to one documentation page and its reviewed source revision or content fingerprint.
- Register a page-worker only after identifying its page and existing capability contracts; record missing contracts as blocked coverage gaps.
- Require the worker to read its assigned page at the pinned revision before handling each task.
- Restrict the worker to its own page's documented scope and authorized capability contracts.
- Return a blocked report for requests outside that scope; let the manager route those requirements to other page-workers.
- Preserve the worker identity when its page changes; review the changed page and capability contracts before updating the registered fingerprint.
- Block undispatched tasks and acceptance of in-flight results when their source fingerprint differs from the registered page.
- Require manager review and a fresh Dispatch work item before executing against the updated page; retain earlier reports as historical evidence.
- Block assignments for deleted pages; update renamed page references through reviewed registry changes.

## 2. Worker report schema

- Persist one harness JSON report per Dispatch work item attempt at the repository-root-relative path `.nevaeh/reports/<task_id>.json`; create `.nevaeh/reports/` when absent.
- Assign task IDs in the manager before dispatch; generate a fresh filename-safe UUID-based ID for every dispatch or retry and require the worker to echo it unchanged.
- Reserve each harness ID by committing `.nevaeh/dispatches/<task_id>.json` before dispatch. Treat an existing reservation or `.nevaeh/reports/<task_id>.json` in the report store as a hard block on a new dispatch; never reuse the ID, overwrite the report or delete it to make room. Recheck the reservation and report path before publication; reject path separators and traversal components.
- Write and commit every harness worker report at that path, then push the commit to a retained branch in the repository before the manager turn ends; do not treat an uncommitted file, a local-only commit, chat output, temporary session state or an external artifact as a substitute.
- Treat a harness worker task as incomplete until the report is committed and pushed, and the manager has read it back from the remote repository at that exact commit and validated its JSON, task identity and status.
- Record the report-store branch and full report commit SHA in the manager's completion receipt so later sessions can retrieve the same file; retain that branch until its report commits are reachable from the shared base branch.
- If the worker cannot write, commit or push the report, return `blocked` with the persistence error instead of `accepted`; let the manager write, commit and push that blocked report at the same path if possible. If neither can persist it, leave the task incomplete and report the persistence failure.
- Use exactly the following fields and nesting for harness reports; replace the illustrative values with actual task evidence.

```json
{
  "task_id": "dispatch-work-item-id",
  "worker": "registered-page-worker-id",
  "source_page": {
    "path": "docs/nevaeh/tutorials/workforce.md",
    "revision": "full-repository-commit-sha",
    "fingerprint": "sha256:page-content-digest"
  },
  "status": "blocked",
  "output": {
    "summary": "Describe the result or blocking reason.",
    "values": {},
    "evidence": []
  },
  "dependencies": [
    {
      "task_id": "upstream-dispatch-work-item-id",
      "report_ref": ".nevaeh/reports/upstream-dispatch-work-item-id.json"
    }
  ]
}
```

- Require nonempty strings for task ID, worker identity, page path, revision and fingerprint.
- Set harness report `status` to exactly `accepted`, `blocked` or `failed`.
- Prepare an `accepted` harness report only after independent acceptance checks pass; do not recognize accepted output or close the task until that report is committed, pushed and read back from its remote commit.
- Set `blocked` for missing contracts, denied authority, stale sources, unresolved dependencies or out-of-scope requests.
- Set `failed` when an attempted execution or its acceptance checks fail.
- Preserve submitted, running and uncertain execution states in Dispatch; do not treat this terminal report shape as the full work-item lifecycle.
- Keep `output.summary` a nonempty string, `output.values` a JSON object and `output.evidence` an array of durable receipt or artifact reference strings.
- Exclude secrets from reports; retain sensitive evidence behind existing account-scoped access controls.
- Record every consumed upstream report in `dependencies`; use an empty array when no upstream output is required.
- Encode each resolved harness dependency as `{"task_id": "<task_id>", "report_ref": ".nevaeh/reports/<task_id>.json"}`; require the filename and the stored report's task ID to match the dependency task ID.
- Require resolved dependencies to contain an accepted report in the authorized scope. Use `unresolved:<task_id>` only as a diagnostic marker in blocked reports; never treat it as a valid report path or dispatchable dependency.
- Validate the report shape, identity, task correlation and source fingerprint before accepting it.
- Retain report files across manager turns and session restarts, associate them with their Dispatch work item and attempt, and use their immutable repository-relative paths for manager retrieval.
- Append corrections and owner acceptance records without overwriting earlier reports.

### Runtime journal boundary

- Reserve runtime UUIDs in the existing `NevaehAgentRun.task_uuid` receipt row, committed with a global unique database index before enqueueing the worker; reject duplicate UUIDs across dispatches and retain reservations. Treat an idempotent replay of the same request as the existing dispatch, never a new task.
- Persist runtime reports in the account-scoped JSONL journal; flush, fsync and read back the validated report before accepting upstream completion. Keep the harness committed-file and remote-read-back rules unchanged.
- Require every runtime dependency to contain exactly `task_id`, `report_ref` and `status`; emit the upstream UUID and `journal:<account_id>:<task_uuid>:<receipt_sha256>`. Map verified runtime `completed` to dependency `accepted` at this boundary; keep runtime lifecycle states in the versioned runtime envelope, not as extra status fields in the dependency record.
- Resolve `.nevaeh/reports/<task_id>.json` from its recorded remote commit in the harness; resolve `journal:` against the authorized runtime account journal and its matching receipt. Reject unknown prefixes, foreign accounts, mismatched UUIDs or hashes, and missing or stale reports. Never reconstruct output from chat, memory or cached goal evidence.
- Block an unresolved dependency before creating its dependent run and recheck the same references before Dispatch execution. Preserve `unresolved:` as a diagnostic marker only; never dispatch from it.

## 3. Manager-to-worker delegation protocol

1. Resolve the request against the page-worker registry and each candidate's documented scope.
2. Split requests spanning multiple pages into separate Dispatch work items; use durable goals to record ordered steps, specialist assignments, dependencies and output expectations.
3. Select only a page-worker whose required capability contracts and executable Dispatch actions already exist. Treat roles and manuals as documentation, not as missing executors.
4. Record a blocked result and a capability gap when no eligible worker or executor exists; do not substitute unsupported model prose for execution.
5. Check for duplicate task IDs in the environment's report store and reservation table; hard-block a collision without dispatching or overwriting. Commit the manager-assigned ID reservation to the harness repository or runtime database, with an immutable task input snapshot containing the work item ID, worker identity, pinned source page, registered capability references, requested action, typed inputs, dependencies and independent acceptance checks.
6. Before delegating any task with dependencies, resolve every `report_ref` using the store and read-back rule above. If its committed harness file or durable runtime journal/receipt cannot be resolved, is invalid or is not accepted at the dependency boundary, record the blocker and do not dispatch. Resolve typed prior-output handoff only from that validated reference, never cached goal evidence, and validate the downstream input contract before dispatch.
7. Apply Gatekeeper permission and account-scope checks before dispatch and again at execution; block denied or stale work.
8. Dispatch the task through the existing Dispatch work item mechanism; retain its run identity and downstream receipts.
9. Observe the persisted work-item state and read back the terminal report through its environment's store; correlate it with the task, attempt, worker and pinned source page. Require the pushed commit and remote read-back for harness reports, or the committed receipt and fsynced journal read-back for runtime reports, before closure. Surface persistence failures as blocked and incomplete.
10. Validate the report and read its output, evidence and dependencies before using the result.
11. Advance dependent durable-goal steps only after accepted output passes the recorded acceptance checks; pass typed values and the immutable report reference onward.
12. Retain blocked and failed reports, surface their reasons and use reviewed retry/revision paths. Reconcile uncertain work before retrying; do not automatically replay it.
