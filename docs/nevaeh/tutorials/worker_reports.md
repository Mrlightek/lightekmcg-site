# SME reports, lessons and Nevaeh's management context

Each specialist has its own operating history. Nevaeh uses that history when coordinating similar work: delegate, collect the actual result, review what worked, retrieve the relevant lesson next time. Improving one SME's tools, documentation and checks improves the work Nevaeh can delegate to it.

## Read and review reports

Open **Nevaeh → Workforce & goals → SME reports & lessons**. Use the **SME reports & lessons** shortcut at the top, then filter by specialist to see its accumulated work. The view displays the latest 40 matching reports and the total available; historical records remain in the database. Deleted specialists retain their reports.

Reports identify the specialist, task/run, service, application, page and downstream execution references. **Open actual execution receipt** opens the existing authenticated receipt. Raw input values, message bodies, service output bodies, credentials and error strings are not copied into report lessons. The report retains a SHA-256 of the receipt and structural status references.

Pending or queued is not success. A completed report means the downstream service reported completion, not that its creative output or business result was correct. Use **Review result or teach this specialist** to record your assessment:

| Assessment | Meaning |
| --- | --- |
| Accepted | You reviewed a completed service result and accepted it. |
| Needs fix | Record what the specialist should check or change next time. |
| Rejected | The result should not be treated as an accepted example. |
| Withdrawn | Stop using the current feedback as a lesson. |

Your lesson or correction can contain up to 2000 characters. Reviews are append-only and tied to the exact receipt digest. If the execution evidence changes, previous feedback remains in its history but is no longer current; review the new evidence again. Pending tasks cannot be accepted, and a failed task cannot be marked accepted.

## How the accumulated work is used

The existing workforce sweep collects reports automatically, including runs that were never opened in the UI. Viewing reports and preparing another delegation also refresh bounded batches. Collection can lag behind very large backlogs; it is not a claim that every run has already been reviewed.

Before a new specialist run is created, the manager consults up to 50 recent matching reports. Its snapshot records the report IDs, outcome counts, up to three accepted lessons and three corrections, and an advisory when failures or rejected results need inspection. The same evidence appears on page-task forms and the manager's response. Each new run still needs its own downstream verification.

Experience is scoped to the same signed-in account, specialist, application and current contract. Role instruction changes, service binding/schema changes and page-contract changes exclude obsolete experience from future matching. Unscoped tasks do not lend their lessons to an unrelated application. Records predating this reporting feature are retained as history without being treated as current-contract lessons.

If an available native language model drafts a conversational response, Nevaeh can retrieve up to three relevant owner-reviewed lessons for the current page/application. A specialist persona consults its own reports; Nevaeh as manager can consult relevant reports across her specialists. Sources are returned as `experience_sources` so the report behind a suggestion can be inspected.

Lessons provide operational context. They never override permissions, change executable payloads, bypass page contracts or automatically activate model checkpoints. Failure reports can identify where investigation is needed; the system does not invent a repair from a status alone. This is persistent retrieval and feedback, not automatic model training after every task.

## Coverage and deployment

This release covers delegated Nevaeh agent runs. Human actions taken directly through other Dashboard pages and existing department audit logs are not yet unified into this reporting stream. The report model is the starting point for that broader activity history.

Run the worker-report migrations, including `CreateNevaehWorkerReports` and `AddStructuredWorkerResults`, then restart Rails and workers. The [structured Reporting System convention](reporting_system.md) defines the required JSON Schema, source rereads, manager journal and file ownership. Reports and owner reviews use two new tables; no external inference or reporting service is required.
