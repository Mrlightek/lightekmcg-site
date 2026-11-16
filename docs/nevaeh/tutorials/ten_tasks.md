# Ten tasks with conversational follow-through

## Ask for the outcome

Use **Nevaeh → Shared workspace** or the Dashboard assistant. Start with one task or connect tasks with “then”. Explicit slash commands retain their existing behavior.

| Task | Example wording |
| --- | --- |
| Draft website page | “Add a web page called About us.” |
| Campaign draft/private preview | “Produce a TikTok advert promoting Lightek services.” |
| Website findings | “Check open website audit issues.” |
| Sales follow-ups | “Find overdue sales follow-ups.” |
| Accounting classification | “Show uncategorized transactions.” |
| Payroll approval queue | “Check payroll drafts due for approval.” |
| Paid fulfillment queue | “Find paid orders awaiting fulfillment.” |
| Onboarding/offboarding | “Review unfinished onboarding.” |
| Saved server health | “Check my servers’ health.” |
| Compliance source freshness | “Find stale compliance monitors.” |

Phrase recognition covers a bounded vocabulary, not arbitrary prose. Nevaeh also offers these ten tasks when you ask what she can do. Existing executors and domain permissions determine whether a task can actually run. A payroll review does not release payments; server status does not repair servers; draft creation does not publish.

## Answer follow-up questions

When required inputs are missing, Nevaeh asks one question at a time. Reply with the requested title, service, website ID/name or employer choice, or use the displayed form. A single accessible website/employer can be selected automatically. Multiple choices require your selection; a name is matched only within the currently authorized list.

Your request and replies persist in an account-owned task dialogue. The shared workspace can resume its active dialogue after reload in the same browser tab. Cancel to abandon it, or say “No, I meant …” to correct a request before dispatch. Corrections to an already saved goal require a fresh request. Dialogue state expires after one day. Paused specialists and revoked permissions still block execution.

## Review plans and observe completion

A complete, recognized single task runs through its assigned worker in Converse/Operate. Plan/Reflect preserves a proposal. Model interpretations require review before dispatch. Multiple tasks create a saved draft goal; review its steps and choose **Start goal**. No action is dispatched just because a plan exists.

For example, “Create a website page called Summer then make a campaign ad promoting Summer services” asks for missing website details and prepares a goal. Same-site steps consume the previous step's site reference through an accepted UUID/journal report, not chat memory. Each step retains its own scope and executor. A failed, missing, stale or unresolved report blocks dependent work. Goals keep the existing twelve-step limit.

## Use the local model without giving it execution authority

The optional local neural interpreter uses a small learned intent-classification head to rank only the ten fixed task labels from an enabled, activated checkpoint trained from a matching task dataset for your account. It does not generate executable code or invent commands, workers, IDs or permissions. Typed inputs come from the request and follow-up answers and are validated against the selected contract. Low-confidence interpretations fall back to normal help; usable model suggestions are identified and require review.

Choose **Prepare local training examples** to save thirty starter phrase/label pairs plus your approved examples as a draft dataset. In Learning & study, use a separate internal task-interpreter model, review and approve the dataset, train for 50 epochs, inspect its task-label acceptance metrics, then activate a passing checkpoint. Keep the ordinary chat model separate; task-only checkpoints are excluded from automatic free-form replies. Account examples require an internal model. The intent head learns vocabulary weighting and softmax weights from the approved corpus; a bounded domain lexicon normalizes common English terms. This is a small task classifier, not a general-purpose language model. No external model API or additional inference server is used, and no checkpoint is silently trained or activated.

## Teach reviewed wording

After a single task actually completes, choose **Teach this wording**, review the phrase and approve it. Nevaeh checks the successful worker receipt and resolves its journal reference before saving an account-scoped example. Queued, blocked, failed, foreign or missing reports cannot establish a successful example. Exact reviewed wording can identify that task again, but previous titles, website IDs and employer IDs are never copied as new inputs.

Training batches remain drafts and preserve source example IDs. Retired examples or changed task contracts invalidate their reuse. Reviewed examples improve recognition within these ten tasks; they do not manufacture new executors or establish general language understanding.

## Deploy and verify

Apply migration `20261116050000_add_nevaeh_task_dialogues` and restart Rails and workers. Existing command and report stores remain authoritative. Test paraphrases for every task, a missing-title conversation, multiple website choices, a saved goal with a real report dependency, replay/cancel, source drift, revoked access, reviewed teaching, and actual local label scoring. Task training holds out one distinct prompt per label and requires at least 80% label accuracy across those ten held-out prompts, in addition to the existing loss/coverage checks. The task interpreter rejects checkpoints without that acceptance evidence. This small evaluation is an initial gate, not proof of general language understanding.
