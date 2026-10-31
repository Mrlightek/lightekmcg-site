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
`ruby test/standalone/nevaeh_backlog_test.rb` — 27 tests, 147 assertions, zero
failures/errors. It uses SQLite/ActiveRecord/ActiveJob and explicit minimal host
adapters; native acceptance above uses the real installed stack.

The existing Rails lifecycle/hardening/recovery suite was attempted locally and
could not boot because private `marlon` dependency access is unavailable in the
local container. Native host verification did boot with the installed engines.

## Release limits

- General ticket-to-repository implementation/promotion remains unfinished; the
  existing reviewed code generators still produce isolated candidates.
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
