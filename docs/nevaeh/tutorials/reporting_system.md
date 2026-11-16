# Reporting System: structured worker convention v1

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

The normative JSON Schema is **`config/nevaeh/worker_report.schema.json`**, identified as `urn:lightek:nevaeh:worker-report:1` and using JSON Schema draft 2020-12. Every report MUST validate before model persistence, journal append or manager journal read. The runtime validator implements the schema's declared types, required fields, enums, exact object properties, bounds, patterns and array uniqueness. Unknown fields, free-text report strings and incomplete objects are rejected.

| Required field | Meaning |
| --- | --- |
| `schema_version` | Integer `1`. |
| `task_id` | Stable `run-N` identity for this specific execution. |
| `worker_id` / `account_id` | Saved worker assignment and account that own the run. |
| `status` | `pending`, `completed`, `failed`, `blocked`, `cancelled` or `evidence_unavailable`. |
| `documentation` | Assigned page path, content SHA-256 and actual pre-execution read time. |
| `output` | Typed authenticated receipt reference, receipt hash and structural execution references. |
| `dependencies` | Earlier goal task IDs and their actual execution states; empty for independent tasks. |
| `file_ownership` | Exact permitted workspace files and the manager-only report writer. |

For example, a successful independent worker emits the following shape. IDs, hashes and times here are illustrative:

```json
{
  "schema_version": 1,
  "task_id": "run-42",
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

## Deployment and review

Run **`AddStructuredWorkerResults`**, then restart Rails/workers. Existing saved operating assignments acquire a documentation contract on their next request. Historical executions without a recorded pre-execution documentation read are not promoted to completed convention-valid examples.

Open **Workforce & goals → SME reports & lessons → Worker JSON report · schema v1** to inspect the structured record, then use the actual execution receipt for output details. This convention covers delegated runs and documentation-page answers; direct human Dashboard activity is still outside the unified stream.
