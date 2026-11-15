# Daily business growth plans

Open **Growth** from the shared Business workspace. **Prepare or open today’s plan** reviews the selected website's business brief, customer queues and recent tracked-link results. The plan gives up to five prioritized moves, each with a reason, practical steps, observed evidence and a button for the appropriate Lightek tool.

The current playbook is `growth-daily-v1`: finish missing business context, review inquiries, check paid orders awaiting delivery, follow through on due sales tasks, review expiring quotes, review an arrived goal date, and then establish campaign drafts, tracked links or distribution. A landing-experience review is suggested only when at least 20 seven-day tracked visits have no recorded attributed inquiry/payment; this threshold is an authored heuristic, not statistical confidence or proof of a conversion failure. Operational queues take precedence over campaign expansion. The list is capped at five.

## Use the operating workspace

In Nevaeh's signed-in operating workspace, enter:

```
/growth SITE_ID
```

Replace `SITE_ID` with the business website ID. `show my growth plan SITE_ID` and `prepare my growth plan SITE_ID` are accepted phrases with the same behavior. In Operate mode this prepares or reuses the latest plan for the application's current day through the existing saved-action/Gatekeeper/Dispatch worker path. The action receipt contains the plan ID, date, revision, playbook version and Dashboard URL. Decide/Reflect modes propose the command without preparing a plan. The result is shared with the website's authorized team.

`/guide growth` opens this tutorial. `/describe growth.plan` shows the installed built-in reference. Eligible accounts also see `growth.plan` in the capability catalog.

## Run daily through an existing agent

To opt into recurring preparation, enter:

```
/agent schedule sage 1440 /growth SITE_ID
```

This uses the existing agent-worker scheduler, not a second scheduler or an external AI API. The interval is 1,440 minutes from scheduling; it does not promise midnight execution or a daily notification. The minute sweep, worker and Dispatch queues must be running. An already prepared plan is reused, so multiple authorized runs on one day cannot create another daily version. The next application day gets a new plan. Use `/agents` and the existing agent controls to inspect runs, run immediately or pause the worker.

The saved agent command uses capability `growth.plan`. If the agent has an explicit allowed-capability list, include `growth.plan` or an appropriate existing prefix. Normal website manager/marketer permissions and the marketing package feature remain required; assigning an agent does not grant them. Authorization is checked at submission, worker execution and plan creation. Lost website access or a disabled marketing package stops scheduled work through the existing blocked/disabled-worker behavior. Inspect the agent run and action receipt before resuming it.

## Work with the plan

- Open the recommended tool and perform the underlying work. Payment, delivery and publication retain their own evidence and authorization.
- **Mark done** or **Dismiss** requires a note. This records who reported the resolution and when; it does not verify a sales task, payment, delivery or publication, and does not change those records.
- **Prepare editable campaign draft** is available only on a campaign-preparation recommendation. It creates one social campaign draft from the plan's reviewed offer, audience, value and customer problem, then opens the native campaign editor. Repeated requests return the same draft. It does not publish, email an audience, generate media or spend money. Review the copy; voice and goal stay available as brief context for the operator and later writing integrations.
- The owner and delegated managers/marketers can edit the resulting campaign. Designers do not gain campaign authoring through this workflow. Mailbox and Studio services retain their own checks.
- **Refresh today’s plan** creates another immutable revision from current evidence. Earlier revisions and resolutions remain in Recent plans. A changed brief requires refresh before drafting. Historical days and superseded revisions cannot be acted upon. If a draft was deleted, refresh rather than retrying its old creation action.

The daily preparation command reuses a plan; only the Dashboard's explicit refresh creates another same-day revision. Refresh requests are idempotent, and stale browser tabs cannot replace the latest revision. Unresolved underlying conditions can recur in a fresh plan even after an earlier recommendation was reported done or dismissed.

## Evidence, limits and recovery

The plan freezes the business brief/revision, the seven-day visit-cohort window, counts used by the playbook, preparation time, creator and rule version. It does not recompute those displayed reasons as new events arrive. The live Growth funnel remains independently filterable. Site data does not cross into another client's plan.

These are explainable authored recommendations over native records. There is no claim of causal analysis, automatic competitor research, general-purpose AI CMO reasoning or guaranteed growth. Missing tracking is not zero website traffic; older/unattributed sales remain unknown. See [Growth Foundation](../../sales/growth-foundation.md) for funnel definitions and attribution limits.

Structured diagnostic events: `lightek.growth.plan_prepared`, `step_resolved`, `campaign_drafted` and `schedule_paused`. They contain site, actor, plan/revision and applicable step/campaign IDs, not business-brief content, resolution-note text, cookie tokens or customer email addresses. Use the in-app plan history and the existing system logs, agent-run history and action receipts to inspect results. Database records and downstream business receipts remain authoritative.

If execution fails, check the website ID and manager/marketer permission, marketing feature availability, assigned agent capability, current brief revision and current plan date/revision. For a stale plan or changed brief, open Growth and refresh. For a paused scheduled worker, resolve the access/provider/queue problem and use the existing agent controls; repeated command submission alone is not evidence of a successful run.

Deploy `20261115150000_add_daily_growth_plans` through the existing per-instance update pipeline before exposing the new code. Retain plan/step tables when reverting code; their snapshots and operator notes are the review history.
