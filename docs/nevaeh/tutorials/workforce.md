# Workforce, goals and page-aware assistance

Open **Dashboard → Nevaeh → Workforce & goals**. This is the directory of specialist roles and the place to assemble delegated work. The directory explains the job behind each name, its department, task templates, connected action contracts and assigned tasks.

## Roles have jobs; tasks perform work

A role is a saved specialist identity, instructions and capability assignment. An assigned task is a concrete instruction with real inputs and an execution history. A goal connects up to twelve one-time tasks in order and waits for their downstream results. The roles use the same operating engine and account authority; they are not twenty-seven separately trained language models.

| Department | Default roles and responsibilities |
| --- | --- |
| Coordination | Nevaeh coordinates saved goals and delegates supported work. |
| Strategy | Sage prepares business growth plans and inspects business work. |
| Creative | Muse writes editable captions, posts and script drafts. |
| Quality | Warden inspects production/rehearsal receipts and audits capability gaps. |
| Studio | Episode Producer, Cast Director, Blocking Technician, Episode Editor and Media Processor prepare scenes, direct registered Cast, rehearse spatial blocking, assemble exports and process files. |
| Distribution | Publishing Coordinator delivers explicitly reviewed masters through configured destinations. |
| Marketing | Campaign Producer builds editable ads/private previews; Growth Analyst prepares evidence-based daily plans. |
| Learning | Manuals Librarian imports documentation; Language Contract Tester checks phrase source/action validity; Language Trainer runs reviewed native training. |
| Engineering | Capability Builder compiles saved construction contracts, emits Ruby service/worker/verifier/test artifacts and runs their acceptance examples. |
| Support | Support Coordinator creates actionable problem tickets. |
| IT | Application Maintainer plans/installs supported Ubuntu packages; Hosting Operator uses connected infrastructure services. |
| Web & Content | Website Operator uses connected website/content capabilities. |
| Sales | Sales Coordinator uses connected CRM and sales actions. |
| Communications | Mail Operator uses connected mailbox/messaging actions. |
| Accounting | Finance Operator uses connected banking/accounting services. |
| People & Payroll | Payroll Coordinator and People Coordinator use connected payroll, directory and onboarding operations. |
| Commerce | Commerce Operator uses connected order, inventory, shipping and catalog operations. |
| Legal & Compliance | Compliance Coordinator uses connected compliance capabilities and retains evidence. |

There are 27 roles including Nevaeh. Existing names, instructions and assignments are preserved. A deleted role stays deleted; revisiting the directory does not silently restore it. **Task templates available** means an instruction template exists, not that every account or provider is configured. **Needs an executable adapter** identifies a role without a matching connected contract. Account permissions are checked when work is submitted and again when it executes.

## Delegate work and manage the team

Select **Assign work**, choose a template and fill in actual names, file names and resource IDs. **Delegate task** submits one concrete instruction. An optional repeat interval creates a scheduled agent worker; its minimum is five minutes. Run, pause and delete assigned tasks in the same directory. Run/Pause still use the existing execution pipeline and receipts.

Use **Pause role** to stop new execution by a specialist. **Delete role** removes it from the active directory and stops future assigned runs, while retaining its record and past receipts for the audit trail. Deleting a task blocks its undispatched queued runs and stops its schedule. Work already dispatched, external effects and a running renderer are not automatically undone. Nevaeh remains the primary coordinator; delete specialist roles or their assigned tasks instead. Create a custom role with the existing plus button if you need a replacement or additional specialist.

Command equivalents:

```text
/agents
/delegate muse /write caption {"topic":"Opening night"}
/agent schedule librarian 1440 /improve corpus
/read agent_workers
/delete agent_workers TASK_ID
/delete agents ROLE_ID
```

Defaults are installed for a signed-in account on first workspace/directory access. Named roles other than the original four resolve by their system key or saved record ID. Existing custom roles keep their owner-scoped capability assignments.

## Save a goal, then start it

Give the goal a concrete name. Add one or more specialist tasks with **Add to goal**. Save the plan and inspect its steps before choosing **Start goal**. Saving a draft does not dispatch it. Plan/Reflect conversation modes also preserve their existing preview-only behavior.

A running goal dispatches the first unfinished task through the existing agent workforce, Gatekeeper and Dispatch. Later steps wait. The minute-based recovery sweep advances goals and recovers queued runs; the initial start also enqueues a goal tick. Each step keeps its actual receipt and configured output expectations.

A queued, dispatched, processing, publishing or training receipt is not completion. Failed, blocked, uncertain, stale and unavailable evidence stop the goal. A construction build must have a verified release and passing saved acceptance examples. Training must pass its recorded acceptance check. Other steps require downstream completion plus their configured output checks; that does not establish the artistic quality of a video or the factual correctness of a generated draft.

**Pause goal** stops progression to additional steps. **Resume checks** inspects the same run again, preserving its identity. It does not silently rerun a failed or uncertain external task. Correct a bad instruction by preparing a fresh goal. **Cancel goal** stops further progression and disables its task workers; already dispatched work may finish.

For integrations, JSON goals support typed references to earlier step receipts. Values are passed as data, never interpolated into executable Ruby or shell text:

```text
/goal {"title":"Build and activate a tested service","steps":[{"key":"build","agent":"capability_builder","command":"/build 123"},{"key":"activate","agent":"capability_builder","command":{"kind":"activate","id":{"$step":"build","path":"result.release_id"}}}]}
/goal list
/goal show GOAL_ID
/goal start GOAL_ID
/goal pause GOAL_ID
/goal resume GOAL_ID
/goal cancel GOAL_ID
```

Replace 123 with an existing reviewed construction. This explicit plan requests activation after the saved build passes verification. A step can additionally specify up to eight `expectations`, such as `{"path":"result.record.name","equals":"Opening Night"}` or `{"path":"result.release_id","present":true}`. Only earlier steps can supply outputs; missing values block execution. Goals are account-owned and repeated request keys cannot create duplicate plans with different inputs.

## Workers that expand Nevaeh

- `/improve gaps` audits the registered capability/schema catalog and page-area connection coverage. It creates an engineering ticket when findings exist. The report is an implementation backlog, not proof of complete application coverage.
- `/improve corpus` queues the existing manual importer, producing real source-linked draft training batches and conversational bindings. Review/activation use the existing learning workflow.
- `/improve language_check` validates active phrase sources and action-contract fingerprints. It reports drift without automatically changing or activating bindings.
- `/build CONSTRUCTION_ID` generates and verifies a service from an existing supported construction contract. `/train MODEL_ID …` runs the existing native trainer on reviewed data. Neither operation invents arbitrary new factory primitives or supplies unrestricted software engineering.

The manual importer now drafts phrases for capability builds/activation, gap audits, manual refresh and language checks as well as the earlier supported tasks. These remain drafts until reviewed. Schedule these tasks using the normal worker interval to perform background maintenance. Review the result before treating a learned phrase, model checkpoint or new service as usable.

## Assistance on the page you are using

Open Nevaeh’s Dashboard dock on a page. She identifies its current area, offers matching connected task templates and links to its guide. Follow-up requests carry the current path/title and numeric site/scene/project context. Recognized task templates still require their inputs; a suggestion never submits itself.

Page-aware questions such as **What can you do here?**, **Explain this page**, or **How do I …?** retrieve the relevant installed documentation for authorized administrators. Client help omits internal document excerpts and uses accessible tutorials. The graphical stage also supplies its active embedded page/production context to requests.

The assistant does not collect password fields, hidden form values or arbitrary query tokens. Context is reference data, not an authority grant. A forged path/site ID cannot bypass the resource policies applied at execution. The assistant can explain a workflow from its documentation even when direct execution is not connected; the gap audit makes those missing connections visible.

The assistant can speak using browser text-to-speech. Its current portrait reacts through status treatments. Studio has lip-sync tooling for registered characters, but this release does not connect the assistant portrait to a facial rig or animate its mouth.

## Deployment and checks

Apply migration `20261115235000_add_nevaeh_workforce_goals`; restart Rails and workers with the existing minute-based WorkflowSweepJob schedule. No extra hosted model is required. Goals use the default queue and existing agent/Dispatch workers.

The standalone checks exercise persisted delegation, typed result handoff, failed output checks, source drift, compilation, manual import, pause/cancel/replay, deleted-role persistence, account isolation, CSRF and page context filtering. Browser fixtures cover role explanations, task/goal actions, deletion/cancel, page-aware assistant suggestions, portrait loading and mobile overflow. Provider-specific execution still requires its deployed account/runtime configuration.
