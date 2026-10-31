# Structured Nevaeh tickets

Tickets use the same typed composition as website pages: ordered action sections,
registered inputs, dependencies, named outputs and independent acceptance checks.
The existing Marlon ticket remains the work order and execution journal.

## Available actions

| Action | Required input | Verified result |
| --- | --- | --- |
| `site.page.create` | Owned site ID, title, slug | Persisted draft page matching title and slug |
| `site.section.add` | Site, draft page, registered section kind and its content fields | Persisted section matching the requested content |
| `studio.project.create` | Project name | Real project, production and default scene with matching relationships |
| `engineering.service.generate` | Reviewed template selection through the action itself | Metadata normalizer tested, committed and pushed on the engineering branch |

The engineering action implements one existing reviewed template. It does not
translate arbitrary prose into an arbitrary feature or run Ruby/shell supplied by
a ticket. Unsupported work requires another reviewed executor and verifier.

## Operator workflow

Create a ticket and select **Use action sections for this ticket**. Add actions
and give each a unique name. A later section may use `@page.page_id` as an input
when the earlier section is named `page`. Reference dependencies are inferred;
additional dependencies use the earlier section IDs. Website content fields come
from the existing section catalog, without a second page builder.

Checking automatic authorization approves precisely the saved revision. Otherwise
use Execute Work Order. Gatekeeper rechecks the actual operator, permissions,
registered capability, environment, revision and work-item binding before work.
Changing a saved order invalidates its authorization. Manual ticket closure is
blocked until structured acceptance succeeds.

Failed tickets retain completed sections. **Revise action sections** changes only
unfinished sections, preserves verified definitions and outputs, records both
revision fingerprints and requires authorization again. Resume uses the same
DymondDispatch work item and reservation. Retry counts are bounded per revision.
An active work item cannot be revised.

## Existing execution pipeline

`ProcessBacklogJob` performs intake. `KnowledgeResolver` reads real KB procedures
and `GithubDevelopmentPlanV7a.from_native_ticket` saves the engineering plan.
`WorkOrder`, `Dispatch`, Nevaeh's capability registry and Gatekeeper retain their
existing roles. The existing DymondDispatch Sidekiq worker executes sections; its
structured hook atomically claims the item and honors the registered queue.
Reconciliation updates the original ticket instead of opening escalation twins.

Each database mutation and its verified receipt share the ticket transaction.
Completed sections are independently verified before being skipped on replay.
Code generation uses a workspace lock, fixed output path, source digest and Git
commit/push verification. KB persistence precedes verified closure. Dash displays
the plan, KB references, blockers, each section and its actual outputs.

## Engineering workspace

`NEVAEH_ENGINEERING_WORKSPACE` may specify a persistent isolated checkout. By
default the worker creates one under `tmp/nevaeh-engineering/workspace`, separate
from the running app's Git repository. Bootstrap and authoring locks serialize
creation and writes. Unrelated edits and conflicting implementations stop work.

`NEVAEH_ENGINEERING_BRANCH` selects the branch; this delivery defaults to
`feat/nevaeh-historical-backlog-20261031`. Main/master/detached HEAD are rejected.
Branch writes use `NEVAEH_ENGINEERING_GITHUB_TOKEN`, or the existing
`GITHUB_ACTIONS_TOKEN`. The credential must already authorize repository writes.
It is passed only to the child Git process and is not written to Git config.
A missing credential, branch or conflicting checkout is an explicit ticket
blocker. Code is not automatically merged or deployed.

Release migration registers the capability in the existing registry. Native
acceptance temporarily enables its own isolated queue and disables that
acceptance-only registration afterward. The migration activates that marked
registration on release, while preserving independently disabled operator policy.

## Verification scope

Local integration exercises real SQLite records, the actual compiler, action
executors, planner and Gatekeeper policy. Native acceptance boots the installed
private engines, uses an actual Marlon ticket and real Sidekiq workers, verifies
actual CMS/Studio records and GitHub branch contents, and saves the KB procedure
before closure. Historical queue acceptance separately verifies pending delivery
through worker shutdown/restart and redelivery.

This does not establish arbitrary ticket coding, production deployment of generated
code, external payment reconciliation, or automatic recovery of every possible
in-flight external operation.


## Actual acceptance evidence (2026-10-31)

GitHub Actions run `41210693377` passed the native historical scan, queue restart
and four-action lifecycle. Actual ticket **27 / LT-6220**, existing work item
**62**, and the original reservation were retained throughout failure, revision
and resume. The verified page was not recreated.

| Artifact | Actual identifier |
| --- | --- |
| Draft website page | Site 1, page 8 |
| Content section | Section 23 on page 8, installed kind `vinylctrl_home` |
| Studio hierarchy | Project 12, production 3, default scene 12 |
| Tested and pushed source | Commit `95b8a0fe734501972447a8dbb0979ad176a898dc` |
| Generated file | `app/services/nevaeh_generated/metadata_normalizer.rb` |
| Verified KB procedure | Article 50 |
| Final ticket state | `resolved`, execution `verified`, work item `done` |

The native check also rejected a saved revision with missing authorization and
redelivered the completed work item without repeating section execution. This
used real Rails/Sidekiq, private Studio/CMS engines, the actual ticket/KB database
and GitHub branch writes. The feature remains on the engineering branch pending
release; the live application checkout was not replaced by this verification.


## Release regression and outstanding CI configuration

After integrating current main, native acceptance run `41211533810` passed with
both recurring jobs preserved. Broader PR CI exposed a mail policy that selected
`sending_policies` and yielded no policy from a process-local mutex. The correction
restores `lightek_mail_sending_policies`, the persisted cross-process row lock,
yielding the actual policy, and honoring the global sending stop. The controlled
PostgreSQL mail regression step passed in CI run `41211759260`.

Full application CI remains blocked before Ruby setup by missing
`LIGHTEK_CI_APP_ID` and `LIGHTEK_CI_APP_PRIVATE_KEY` credentials for private engine
reads. Native installed-stack acceptance is separate evidence and does not make
those skipped security, lint and full-suite checks pass. The PR remains unmerged
and general production acceptance is not claimed.
