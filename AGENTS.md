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

- Persist one JSON report per completed Dispatch work item attempt.
- Use exactly the following fields and nesting; replace the illustrative values with actual task evidence.

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
      "report_ref": "immutable-upstream-report-reference"
    }
  ]
}
```

- Require nonempty strings for task ID, worker identity, page path, revision and fingerprint.
- Set `status` to exactly `accepted`, `blocked` or `failed`.
- Set `accepted` only after independent acceptance checks pass and accepted output is retained.
- Set `blocked` for missing contracts, denied authority, stale sources, unresolved dependencies or out-of-scope requests.
- Set `failed` when an attempted execution or its acceptance checks fail.
- Preserve submitted, running and uncertain execution states in Dispatch; do not treat this terminal report shape as the full work-item lifecycle.
- Keep `output.summary` a nonempty string, `output.values` a JSON object and `output.evidence` an array of durable receipt or artifact reference strings.
- Exclude secrets from reports; retain sensitive evidence behind existing account-scoped access controls.
- Record every consumed upstream report in `dependencies`; use an empty array when no upstream output is required.
- Require each dependency reference to resolve to an accepted report in the authorized scope.
- Validate the report shape, identity, task correlation and source fingerprint before accepting it.
- Store reports durably under their Dispatch work item and attempt; expose an immutable report reference for manager retrieval.
- Append corrections and owner acceptance records without overwriting earlier reports.

## 3. Manager-to-worker delegation protocol

1. Resolve the request against the page-worker registry and each candidate's documented scope.
2. Split requests spanning multiple pages into separate Dispatch work items; use durable goals to record ordered steps, specialist assignments, dependencies and output expectations.
3. Select only a page-worker whose required capability contracts and executable Dispatch actions already exist. Treat roles and manuals as documentation, not as missing executors.
4. Record a blocked result and a capability gap when no eligible worker or executor exists; do not substitute unsupported model prose for execution.
5. Create an immutable task input snapshot containing the work item ID, worker identity, pinned source page, registered capability references, requested action, typed inputs, dependencies and independent acceptance checks.
6. Resolve dependencies through typed prior-output handoff from accepted reports; validate the downstream input contract before dispatch.
7. Apply Gatekeeper permission and account-scope checks before dispatch and again at execution; block denied or stale work.
8. Dispatch the task through the existing Dispatch work item mechanism; retain its run identity and downstream receipts.
9. Observe the persisted work-item state and retrieve the terminal report through its stored reference; correlate the report with the task, attempt, worker and pinned source page.
10. Validate the report and read its output, evidence and dependencies before using the result.
11. Advance dependent durable-goal steps only after accepted output passes the recorded acceptance checks; pass typed values and the immutable report reference onward.
12. Retain blocked and failed reports, surface their reasons and use reviewed retry/revision paths. Reconcile uncertain work before retrying; do not automatically replay it.
