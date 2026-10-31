# Historical ticket backlog execution

Branch: `feat/nevaeh-historical-backlog-20261031` (base main `3b75ddb`).

`Marlon::Ticket` remains authoritative. `NevaehIntelligences::ProcessBacklogJob`
scans unresolved records in bounded pages and queues ticket IDs. New tickets enqueue
after commit. The existing Sidekiq cron reloads a sweep every five minutes, recovering
committed tickets whose initial enqueue failed. `NEVAEH_BACKLOG_ENABLED=0` pauses
both intake and sweeps. `NEVAEH_BACKLOG_ACTOR_ID` selects a persisted operator;
this configuration never grants permissions or bypasses Gatekeeper.

`TicketBacklog` stores analysis, engineering plans, KB references, classification,
failure counts and actual blockers in `extra_fields.nevaeh_backlog`. It composes
the existing WorkOrder, GithubDevelopmentPlanV7a, STUDIO-203 discovery bridge,
KnowledgeResolver, TicketExecution and recovery evidence. It does not create
another executor. Explicit structured requirements can create native work orders;
missing acceptance requirements are escalated rather than fabricated. Existing
orders and execution reservations are preserved. Repeated identical analysis does
not create duplicate timeline events. Failure counts persist on the ticket; five
failures require an operator resume or changed input. The Dash resume action resets
analysis retries without clearing execution receipts, reservations or approvals.

Only the existing Studio project-creation executor is supported. Automatic acceptance
is limited to its documented persistence checks. A registered capability, generated
candidate or a completed WorkItem alone does not establish acceptance. Backlog
closure checks the persisted hierarchy, ticket ownership and saved revision hashes,
then saves a reusable KB lesson before resolving. KB failure rolls back closure;
reconciliation can retry without creating another project. Generic KB lessons no
longer receive an unrelated controller exception or diagnosis.

Dash's Nevaeh overview includes database-derived ticket/processing counts and up to
100 unresolved records with blockers. Ticket detail exposes saved engineering plans,
KB IDs and operator resume. GET requests do not dispatch work.

## Verification completed in this session

`ruby test/standalone/nevaeh_backlog_test.rb`: 17 tests, 92 assertions, zero failures
or errors. This controlled integration uses SQLite, ActiveRecord 7.2 and ActiveJob
with minimal host/engine adapters. It loads actual changed ticket services and jobs.
It verifies intake, paged historical discovery, exact capability/KB matching,
native work orders, repeated delivery, bounded persistent failures, resume,
dependencies, production denial, KB persistence/rollback, receipt ownership and
acceptance refusal. It is not a production or real-Sidekiq restart acceptance test.

The existing `bin/nevaeh-test` lifecycle/hardening/recovery run was attempted and
failed before boot: private `git@github.com:lightekmcg/marlon.git` is unavailable.
No Rails regression success is claimed.

## Open acceptance work

- Read actual production Marlon ticket and KB records; the browser currently shows
  the Lightek sign-in screen and this environment has no production SSH credential.
- Implement repository-changing engineering execution through the existing approved
  pipeline; current candidate generators remain isolated/review-only.
- Extend verified executors/acceptance contracts for the actual backlog requirements.
- Production dispatch remains disabled by existing Gatekeeper/worker policies.
  No policy was removed to claim completion.
- Verify PostgreSQL concurrency, real Sidekiq crash/restart recovery, live Dash,
  deployment behavior and ticket-specific acceptance against the installed app.
- Execute real backlog tickets and record actual IDs/outcomes. None were retrieved,
  executed, resolved, declared duplicate or declared obsolete in this session.

No completion PR has been opened. This branch is not production-accepted.
