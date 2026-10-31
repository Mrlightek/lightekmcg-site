# Historical backlog execution

Engineering branch: `feat/nevaeh-historical-backlog-20261031`.

## Implemented

Marlon tickets remain authoritative. `ProcessBacklogJob` discovers unresolved
records in bounded pages; new records enqueue after commit; Sidekiq cron sweeps
committed tickets every five minutes. `NEVAEH_BACKLOG_ENABLED=0` pauses intake.
`NEVAEH_BACKLOG_ACTOR_ID` selects a persisted operator and never grants permissions.

`TicketBacklog` composes the existing WorkOrder, development planner, STUDIO-203
registry bridge, KnowledgeResolver, TicketExecution and recovery services. Actual
Gatekeeper/WorkItem incident references produce native recovery work orders with
incident-specific acceptance criteria. Related Gatekeeper operations are linked
without assuming they are duplicates. Existing orders, approvals, reservations,
receipts and diagnostics are retained. Missing requirements and unsupported
executors produce explicit blockers on the original records.

Job receipts persist in ticket extra_fields. Completed ActiveJob IDs skip repeated
delivery. Analysis failures are bounded to five attempts and can resume through
the authorized Dash action without clearing an operation reservation. The bounded
job journal supplements the existing execution-level idempotency controls.

Backlog-managed Studio closure checks persisted artifacts, ticket ownership, work
order/input fingerprints and supported acceptance criteria. KB persistence happens
before resolution and rolls back closure if it fails. Generic KB lessons no longer
receive an unrelated controller-error diagnosis.

Historical deployed fixes have a separate verification path: authorized operator,
original incident identity, existing work order, installed component loading,
HTTPS health, worker readiness and revision evidence must agree. The original
failed deployment operation is preserved. Verified procedures are saved in KB
before closure. Obsolete/duplicate outcomes require an authorized operator and
written provenance; they cannot override a reserved execution or claim a verified
implementation.

Dash reads real ticket/processing counts, saved plans, blockers, KB references and
execution evidence. The resume action preserves execution authorization boundaries.
The deployment workflow reports the deployment step's outcome independently from
later acceptance steps; a failed downstream check no longer falsely marks a
successful deployment as failed.

## Native verification

The acceptance workflow reuses the existing deployment SSH identity, environment
file, app user, Ruby and installed private engines. Candidate services load in a
separate Rails process; the live checkout and production workers are not replaced.
Actual ticket plans and evidence are persisted in the installed database. Private
source diagnostics stay in internal ticket evidence; CI prints aggregate counts.

Successful native run: GitHub Actions `41205472641`.

- Real historical ticket discovery and work-order/plan persistence passed.
- Three historical application-boot incidents were verified resolved; their KB
  procedures are visible in the live Knowledge Base. Original failed operations
  were not rewritten as successes.
- Installed application eager loading, HTTPS 200 and active Sidekiq were observed.
- A real Sidekiq worker on a unique acceptance queue was quieted, a real existing
  ticket job was queued, and the worker was stopped/restarted. The queued job
  survived, processed the actual ticket and suppressed duplicate completion on
  redelivery. The production worker service remained running.

This proves pending-job restart/replay behavior, not an abrupt in-flight media
mutation crash or every possible external operation's idempotency.

Local controlled persistence integration:
`ruby test/standalone/nevaeh_backlog_test.rb` — 33 tests, 183 assertions, zero
failures/errors. It uses SQLite/ActiveRecord/ActiveJob and explicit minimal host
adapters; native acceptance above uses the real installed stack.

The existing Rails lifecycle/hardening/recovery suite was attempted locally and
could not boot because private `marlon` dependency access is unavailable in the
local container. Native host verification did boot with the installed engines.

## Release limits

- Structured tickets now execute registered CMS/Studio actions and commit one
  reviewed engineering template; see `structured_ticket_execution.md`. Arbitrary
  ticket-to-code implementation and automatic production promotion remain outside
  the verified executor set.
- Production dispatch retains the existing Gatekeeper/worker restrictions. No
  generic production executor or approval bypass was introduced.
- The media registry has no verified ticket executors for the historical handlers;
  Blender is absent on the installed host. The trim stream-lifetime fix already
  exists in the installed private engine but its original render is not accepted.
- Financial incidents remain unresolved pending ledger/provider reconciliation
  and appropriate authorization. No charge, transfer or payment replay occurred.
- Deployment acceptance failures and the installed checkout's uncommitted changes
  require their specific follow-up; unrelated successful checks do not resolve them.

The branch is not claimed to satisfy full production acceptance. No incomplete
completion PR has been opened, and no merge to main was performed.


## Historical ticket outcomes

The identifiers below are actual database ticket IDs. They are not substituted
examples. Original failed operations remain intact.

| Ticket IDs | Outcome | Actual evidence or blocker |
| --- | --- | --- |
| 17 (LT-6968), 18 (LT-7367), 19 (LT-8004) | Verified resolved | Installed application loads the repaired mail callback, Dashboard namespace and mail policy; HTTPS 200, active Sidekiq and individual KB procedures were recorded before closure |
| 2 (LT-3277) | Documented obsolete | Intentional NonexistentHandler/test_failure work item 14 |
| 13 (LT-6581) | Documented obsolete | The same GitHub workflow subsequently succeeded |
| 16 (LT-9572), 24 (LT-2110) | Documented duplicate | Canonical tickets 15 and 23, respectively |
| 1 | Escalated | Bank authorization requires investigation and the actual bank integration's authorization |
| 3 | Escalated | Requested behavior and acceptance requirements are missing |
| 4 | Escalated | Trim stream-lifetime fix exists, but the original render has not passed acceptance and has no registered ticket executor |
| 5, 6 | Escalated | Blender executable is absent; historical timeline/scene rendering is not verified |
| 7, 8, 9, 10, 11 | Escalated | Invoice 12 remains open/unpaid; failed provider attempts require ledger/provider reconciliation before any replay |
| 12, 14, 15, 20, 21, 22, 23, 25, 26 | Escalated | Original deployment or downstream paid-release acceptance failure needs its own target-revision and failed-step verification; generic health does not satisfy it |

Ticket 26 was created by a later real deployment failure and was discovered by the
next sweep. It received an incident work order, KB lookup and recorded blocker.


Controlled lifecycle ticket 27 (LT-6220) was verified resolved with actual page,
section, Studio, code and KB outputs. Ticket 28 (LT-6962) is the original failed
work-item escalation twin, linked to the same item 62 and reservation; it is
reconciled against canonical ticket 27 after that ticket's verified closure.
