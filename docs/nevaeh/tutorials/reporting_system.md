# Reporting System: structured worker convention v2

This is the executable convention for documentation-page SMEs and delegated Nevaeh workers. **MUST** and **MUST NOT** describe enforced boundaries; deployment and coverage are specified below.

## Architecture and responsibilities

Nevaeh is the manager: receive the requirement, select the page SME or operating worker, submit a task, collect its execution result, validate its report and save it to the shared account journal. Workers do not append to the journal themselves.

A documentation SME corresponds to exactly one installed tutorial page. Use:

```text
/page agents How do I delegate a task?
/page studio How do I work with assets?
/page reporting_system What does a report contain?
```

The first request creates an account-owned `page_TOPIC` SME with only documentation-question/answer capabilities. Its identity stays assigned to that page. Different questions create task runs; identical saved instructions can reuse their worker assignment. Selecting that SME and asking a conversational question routes back through its own page worker. Disabled or deleted SMEs are not silently restored.

The worker MUST read the page from disk before executing or answering. It MUST check its assigned path, source SHA-256, capability and immutable instruction digest. A changed page or instruction requires a fresh assignment. Prior lessons and model memory MUST NOT replace this read. Page answers contain exact excerpts and line references from that page only. No matching passage returns a blocked result to the manager; the worker does not invent an answer or search other pages.

Operating assignments also bind to one documentation page and one concrete instruction. Existing named department roles can supervise multiple such assignments; a saved worker assignment cannot silently switch its page or task. Native services still enforce their own account/resource policies.

## Fixed report schema

The normative JSON Schema is **`config/nevaeh/worker_report.schema.json`**, identified as `urn:lightek:nevaeh:worker-report:2` and using JSON Schema draft 2020-12. Every report MUST validate before model persistence, journal append or manager journal read. The runtime validator implements the schema's declared types, required fields, enums, exact object properties, bounds, patterns and array uniqueness. Unknown fields, free-text report strings and incomplete objects are rejected.

| Required field | Meaning |
| --- | --- |
| `schema_version` | Integer `2`. |
| `task_id` | Manager-assigned UUID reserved before worker execution. |
| `worker_id` / `account_id` | Saved worker assignment and account that own the run. |
| `status` | `pending`, `completed`, `failed`, `blocked`, `cancelled` or `evidence_unavailable`. |
| `documentation` | Assigned page path, content SHA-256 and actual pre-execution read time. |
| `output` | Typed authenticated receipt reference, receipt hash and structural execution references. |
| `dependencies` | Upstream UUIDs, resolvable `report_ref` values and boundary statuses; empty for independent tasks. |
| `file_ownership` | Exact permitted workspace files and the manager-only report writer. |

For example, a successful independent worker emits the following shape. IDs, hashes and times here are illustrative:

```json
{
  "schema_version": 2,
  "task_id": "8a5b02ca-59c0-4e2d-91cb-fb425c0c0b49",
  "worker_id": 12,
  "account_id": 7,
  "status": "completed",
  "documentation": {
    "path": "docs/nevaeh/tutorials/agents.md",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "read_at": "2026-11-16T01:00:00Z"
  },
  "output": {
    "kind": "receipt_reference",
    "action_id": 82,
    "receipt_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "references": [{"id": 82, "type": "documentation_answer", "status": "completed"}]
  },
  "dependencies": [],
  "file_ownership": {
    "workspace": "worker_workspace",
    "write_files": [],
    "report_writer": "manager"
  }
}
```

`output` points to the actual authenticated service result rather than copying arbitrary message bodies or credentials into the reporting corpus. A completed service receipt does not imply owner acceptance or artistic correctness. Existing explicit owner reviews remain separate and bound to the receipt hash.

## UUID reservation and dependency resolution

Reserve each new dispatch UUID in `nevaeh_agent_runs.task_uuid` before its worker is enqueued. The global unique database index rejects concurrent reuse across accounts and workers; an existing journal task ID also blocks a new reservation. A replay of the same worker/request key returns the original dispatch, not another run. Retain UUIDs when roles or tasks are paused/deleted. Apply `ReserveNevaehTaskUuids` and restart Rails and workers; the migration assigns stable UUIDs to historical runs without deleting their original journal entries.

Use exactly this runtime dependency shape:

```json
{
  "task_id": "8a5b02ca-59c0-4e2d-91cb-fb425c0c0b49",
  "report_ref": "journal:7:8a5b02ca-59c0-4e2d-91cb-fb425c0c0b49:0000000000000000000000000000000000000000000000000000000000000000",
  "status": "accepted"
}
```

`journal:` identifies the account, reserved UUID and receipt SHA-256. The manager loads the account journal entry, checks the UUID and completed execution state, compares it with the stored worker report, and validates the referenced authorized action receipt's hash. It then reads typed outputs through that receipt. Missing, foreign, malformed or changed evidence blocks the dependent task, even if cached goal evidence or a database report still exists. Recheck references after queueing and before Dispatch to catch evidence removed in between. Do not repair a missing report inside dependency resolution.

Keep `completed` as an internal runtime lifecycle state. Emit only `accepted` in a successfully verified dependency record at the contract boundary; this is not an owner review or a claim of artistic quality. Goal steps must also pass their saved output expectations before downstream work can start. Publish, fsync and read back the first report before marking its goal step complete.

Keep harness references as committed `.nevaeh/reports/<task_id>.json` paths with exact remote-commit read-back. Do not replace them with run-N IDs or waive their commit requirement. Runtime journal durability uses the committed receipt database plus fsynced journal; it does not publish private operational reports to Git.

Read version-1 journal entries using their frozen historical schema, but do not resolve run-N records as UUID dependencies. Existing report views can publish validated version-2 records under migrated UUIDs; unresolved historical goal evidence remains blocked until its upstream reports are available. Do not rewrite historical journal lines.

## Manager-owned shared file

Each account has one private journal at:

```text
storage/nevaeh_worker_reports/account-ACCOUNT_ID/reports.jsonl
```

Each line is one complete schema-valid JSON report. The same task can append a new revision when downstream status changes; unchanged reports do not append duplicate events. `task_id` identifies the latest revision. The manager uses exclusive file locking, flush and fsync for appends; readers use shared locking. Journal files are mode `0600`, created inside private managed directories. Symbolic links are rejected.

The existing database retains the execution record and structured result. When retrieving experience, the manager reads the JSON journal, validates the record, checks its account, and compares it with the corresponding database execution result. A missing, malformed or mismatched journal record MUST NOT become learned evidence. There is no fallback that treats a plain-text answer as a report.

Journal reads are bounded to the latest 8 MB. Older execution history remains in the database; reading older records through the report view recaptures their current evidence and republishes a validated revision when needed. Back up the journal alongside application storage. A failed append can be retried from the persisted execution record; it is not proof the underlying task failed or succeeded.

## File ownership and parallel work

Every assignment starts with **`write_files: []`**. It has no permission to author shared workspace files. Report files belong exclusively to the manager and live outside the worker workspace.

When a managed file-writing adapter is used, the manager MUST declare distinct exact relative file paths before the first run using `DocumentationWorkers.assign_files!`. Declarations cannot change after a run exists. No wildcard, absolute path or `..` traversal is accepted. The managed writer `DocumentationWorkers.write!`:

1. Rereads the assignment's documentation and checks specialist authority.
2. Rejects finished/blocked tasks and undeclared paths.
3. Rejects overlap with any other active account worker that declares that exact file.
4. Serializes the ownership check/write under the account database lock.
5. Rejects symlinked directories/files and atomically replaces only the assigned file.

For example, give one worker `scripts/episode_01.md` and another `storyboards/episode_01.json`. Two active workers assigned `scripts/episode_01.md` cannot write it until the manager resolves the overlap. Workers MUST NOT edit arbitrary repository files or the report journal through this writer.

This boundary covers the managed worker-file API under `storage/nevaeh_worker_files/account-ID/`. Existing Studio/media engines retain their own artifact storage and native authorization; this convention does not claim to sandbox arbitrary shell processes or transparently intercept every filesystem write in third-party software.

## Authoritative store and rollout

Bind a dispatch to one store. A committed `.nevaeh/reports/<task_id>.json` path belongs to the harness and requires remote-commit read-back. A `journal:` reference belongs to the runtime and requires the matching account journal entry and receipt. Never try both stores or fall back to run-N, cached goal evidence, chat or memory when the authoritative entry is absent.

The backfill policy is **one-time assigned UUIDv4**, not a fresh UUID on every deployment. `ReserveNevaehTaskUuids` fills every existing run before applying NOT NULL and the global unique index. The retained run primary key permanently maps `run-N` to its assigned UUID. `BackfillNevaehReportReferences` reuses that mapping for historical reports and queued dependency snapshots, appends validated v2 journal entries, and preserves v1 journal lines. Re-running it does not change UUIDs or add identical journal entries. Missing/mismatched journal evidence becomes blocked, never accepted from a database/cache copy. Incomplete receipt metadata blocks dispatch during the transition; a foreign/orphan legacy dependency stops the migration for repair.

Use the deployment script's ordered maintenance window:

1. Stop Sidekiq gracefully and stop web/Cable writes before migration. Leave queued jobs in the queue.
2. Run both migrations and the data backfill, then asset/boot checks. On failure, leave consumers stopped; do not run mixed schemas.
3. Prepare Passenger's environment, restart Rails/Apache and pass the web health check.
4. Start Sidekiq, then Cable. Do not restart workers ahead of the web release.

There is no `report_ref` database column: references are fields inside the versioned structured report and immutable run snapshot. A receipt without populated/validated dependency metadata remains blocked until its migration or normal publication completes.

After deployment, run the opt-in acceptance on the actual host with a super-admin test account (the example uses account 1):

```bash
LIGHTEK_RUN_RUNTIME_REPORT_ACCEPTANCE=1 LIGHTEK_ACCEPTANCE_ACTOR_ID=1 bin/rails runner script/lightek/nevaeh_runtime_report_acceptance.rb
```

This uses the real job queues and Gatekeeper for one read-only edge. It pauses the goal after the upstream run, verifies its UUID journal reference, changes only the test goal's cached value, and proves the manager still reads the journal-derived integer. It durably backs up and temporarily removes only that test UUID's journal entries, verifies missing-entry resolution blocks downstream dispatch despite the database/cache copies, and restores the entry and cached evidence in `ensure`. It then resumes the goal and verifies the completed downstream run retained the resolved UUID/reference/accepted dependency. Other journal entries are preserved. The receipt and recovery backup are mode 0600 under `storage/nevaeh_acceptance/`; a successful result requires active deployed workers and is separate from local test results.

## Deployment and review

Run **`AddStructuredWorkerResults`**, then restart Rails/workers. Existing saved operating assignments acquire a documentation contract on their next request. Historical executions without a recorded pre-execution documentation read are not promoted to completed convention-valid examples.

Open **Workforce & goals → SME reports & lessons → Worker JSON report · schema v2** to inspect the structured record, then use the actual execution receipt for output details. This convention covers delegated runs and documentation-page answers; direct human Dashboard activity is still outside the unified stream.
