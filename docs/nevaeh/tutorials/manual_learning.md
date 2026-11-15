# Installed manuals, neural learning and conversational tasks

Open **Digital Factory → Manuals & Language**. The installed README files and documentation become a versioned corpus for the existing native neural model. Separately reviewed conversational phrases bind everyday requests to exact supported operating actions. Recurring requests use the existing agent workforce, Gatekeeper, Dispatch and execution receipts.

## Build the installed manual corpus

Choose **Build corpus & draft conversational phrases**. The existing background worker imports documentation eligible for Software Library, retaining document paths, titles and source checksums. Software Library excludes hidden paths, symlinks, vendor/node_modules, temporary files, tests and files over its 512 KB document budget. The whole import is capped at 16 MB. The import does not fetch external sites or evaluate code examples.

The builder splits headings and source text into bounded training parts. Long code tokens and URLs are split without silently discarding their remaining text. Parts fit the native network's response-token budget; each pair records its source, section and part. Batches obey the existing row and UTF-8 byte budgets and begin as drafts. A successful build can be read repeatedly without duplicating its datasets.

Review the build's manifest and **Review batch** links. **Approve reviewed source batches** approves the current source-derived batches as one transaction, after checking that the installed files and examples still match their provenance. Individual approvals in Neural training and `/approve DATASET_ID` also check this provenance. A changed file or edited source-derived example requires a new reviewed build or a separately authored teaching dataset.

## Train the native model across approved batches

Select an enabled **internal** language model and epochs per batch, then choose **Train approved batches sequentially**. The plan uses the existing training recovery sweep; no additional inference service is needed.

Each plan requests one batch, waits for the real trainer, checks its acceptance evidence, activates a passing checkpoint, and requests the next batch from those weights. The optimizer still measures training/held-out loss, vocabulary coverage and bounded retention. It is not a text-generation placeholder. A failed acceptance check, changed approval, source drift, revoked authority or stale checkpoint lineage blocks the plan and retains the error. Other queued/running training has priority over starting another batch.

Use **Pause plan** to cancel a queued trainer or stop a running plan at its next guard check. **Resume remaining batches** rechecks approval/source state and creates a fresh request attempt at the unfinished position. A plan completes one pass over its selected corpus; it does not loop indefinitely. Its actor, source IDs, active run, accepted position and run snapshots provide provenance.

This extends the current small fixed-window model; it does not turn it into a large general-purpose model. The existing 2,048-token vocabulary, 64-hidden-unit maximum, context window and training budgets still constrain learning. A broad corpus can exceed vocabulary coverage or fail validation. The plan blocks rather than treating unknown-token prediction as mastery. Low optimizer loss does not establish broad comprehension, factual reliability or operational competence.

## Draft language bindings from the live system

The builder inspects the installed capability and resource catalog. It drafts conversational templates for known project/ticket/worker operations, accessible resource listing, and connected capabilities with scalar input contracts. For a connected capability missing its registry schema, an explicit JSON command example in an installed manual can supply a **draft** scalar input mapping for review. Examples remain data; no Markdown instruction is automatically executed.

The coverage report distinguishes disabled, unconnected, workflow-only and structured-input actions. It also lists manuals without an explicit source binding. This is a report about registered contracts and source mappings, not proof that every feature mentioned anywhere is implemented or automatable. Structured/ticket-only work retains its existing worker pipeline. Missing executors and verifier/schema implementations still need engineering work.

Inspect **Exact action and sources** before activating a phrase. **Activate reviewed conversational phrases** activates a build's valid drafts as one transaction. The separate editor lets administrators add or revise wording, typed slots and an exact operating-command template linked to an installed manual. Editing a binding returns it to Draft. Pause a phrase to disable it.

Example:

```json
{
  "patterns": ["make a studio project called {name}"],
  "slots": {"name": "string"},
  "command_template": {"kind": "project", "name": "{name}"}
}
```

Supported slots are `string`, `integer`, `number` and `boolean`. A placeholder fills a whole command value. It is never interpolated into Ruby, shell text or JSON source. Each activated binding pins its reviewed action-contract checksum as well as source checksums. Changed phrases, manuals or contracts block stale tasks, including queued/scheduled tasks. Runtime guards verify that the saved action still matches the exact reviewed template; a binding stamp cannot authorize a different command.

## Converse and automate

After activating the relevant binding, examples include:

- `Could you please make a studio project called Launch Night`
- `Show me my workers`
- `Every 60 minutes, run worker 12`

Replace names and IDs with real accessible values. The selected agent remains subject to its existing enabled state, allowed capabilities and account/resource scope. Scheduling uses the existing 5–525,600 minute interval contract. Unknown instructions remain questions or clarification requests; ambiguous phrases do not dispatch an action.

For a recognized task missing inputs, Nevaeh displays an in-chat task-input form. The submitted binding ID, fingerprint and typed values preserve the requested action and recurring interval. Inputs from one task are not guessed from unrelated chat messages. Retrying unchanged form inputs reuses the action request key. Plan/Reflect modes remain read-only previews.

The conversational action layer is an explicit, teachable pattern/typed-contract system. The separate neural model learns language from the source batches and produces drafts. This release does not treat arbitrary neural-generated text as an executable plan or provide unrestricted semantic understanding of every paraphrase. You can expand the reviewed phrase vocabulary as the system grows.

## Authority, receipts and deployment

Operational manuals and their global language bindings remain administrative. Existing signed-in user permissions, agent restrictions, resource ownership and Gatekeeper checks are applied both at submission and execution. Personal memory-consent behavior is unchanged. Generated responses alone do not activate capabilities, approve datasets or change access.

Run migration `20261114230000_create_nevaeh_manual_learning` and restart the existing application and worker/scheduler. The existing factory recovery job also advances learning plans. README, FEATURES and this guide describe the current boundary; installed execution receipts remain the evidence for completed work.

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/nevaeh_manual_learning_test.rb --name '/NevaehManualLearningTest/'
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/nevaeh_manual_conversation_test.rb
node --test test/javascript/nevaeh_task_inputs_test.cjs
```
