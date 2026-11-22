# Daily business growth plans

For a guided week of actual campaign drafts and existing-lead follow-through,
open [Marketing copilot](marketing_copilot.md) from Growth, or use
`/marketing SITE_ID`. It prepares a seven-day kit while retaining the daily
plan's evidence, native approvals and real outcome tracking described below.

Open **Growth** from the shared Business workspace. **Prepare or open today’s plan** reviews the selected website's business brief, customer queues and recent tracked-link results. The plan gives up to five prioritized moves, each with a reason, practical steps, observed evidence and a button for the appropriate Lightek tool.

The current playbook is `growth-daily-v3`: finish missing business context, review inquiries, check paid orders awaiting delivery, follow through on due sales tasks, review expiring quotes, review an arrived goal date, and then establish campaign drafts, tracked links or distribution. A landing-experience review is suggested only when at least 20 seven-day tracked visits have no recorded attributed inquiry/payment; this threshold is an authored heuristic, not statistical confidence or proof of a conversion failure. Operational queues take precedence over campaign expansion. The list is capped at five.

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

## Review and produce campaign content

From the campaign editor, open **Content variations & approval** to use the shared writing engine for offer, problem and benefit drafts. Saved-copy approval binds the payload used by existing sends/publication. Social campaigns select portrait, square or landscape Studio production; reopening preserves edits, and script replacement is explicit. See [the full content and Studio workflow](../../sales/campaign-content-review.md). This workbench is available in Dashboard; `/growth` continues to prepare recommendations rather than automatically approve or publish content.

The [Publishing calendar](../../sales/publishing-calendar.md) now handles final Studio export attachment and reviewed social scheduling from Dashboard. `/growth` remains a planning command; it does not automatically schedule or publish external messages.

## Campaign performance and follow-up experiments

Open **Business → Performance**. Prepare a comparison after completing the growth brief and explicitly approving two social campaigns. Record a hypothesis, one intended difference, a 1–90-day visit window, source/medium and each local destination path. Confirm the intended placement. Lightek saves the brief/audience/offer, reviewed copy, approval actor/time and exact payload digest, then binds a separate immutable tracked link to each arm. When the reviewed CTA already uses a native campaign tracking link, match its enabled source, medium and destination; Lightek binds that link. Otherwise it creates a new placement link. A link already bound to a comparison cannot be reused. Use each link alongside its assigned version. Nothing is injected into the campaigns or published; inserting a new URL into approved copy changes its digest and requires new approval and a new comparison. Earlier visits on an existing link are excluded: measurement begins at the later of version pinning and the first visit day. Older visits do not establish creative-version attribution.

**Measure a fresh review**, or enter:

```text
/growth review SITE_ID COMPARISON_ID
```

This is capability **`growth.review`**, through the existing saved-action/Gatekeeper/Dispatch path. Each action saves one immutable timestamped review; retries of that action return its receipt. A new command request measures a new review. It counts native tracked visits during the saved window and independently records attributed inquiry, lead, deal, order, confirmed-payment and delivery stages. Stage counts are distinct visits, not orders. Order amounts and refunds are shown by currency; they are not profit or processor settlement. Downstream outcomes known at measurement can arrive after the visit window; later reviews can differ while earlier snapshots remain unchanged.

Matching calendar receipts are grouped by their pinned campaign digest and scheduled window. Scheduled/submitted/published states are operational evidence, not views or conversions. Manual/other publication is outside those counts. Impressions, likes, spend, untracked traffic and actual audience allocation are unavailable, not zero. There is no randomized traffic split or causal winner. Source/medium and the brief describe intended placement/audience, not proof of exposure. Bots, previews, cookie/privacy limits and cross-device visits retain the existing attribution limitations.

The authored review rule requires at least **30 tracked visits per placement** and waits until **seven full days after the visit window closes** before enabling a follow-up starting draft. These thresholds are not statistical confidence. Missing coverage prompts collection, changed approval/copy/media or a disabled link prompts repair, and an unfinished outcome window prompts waiting. With sufficient mature observations, exact payment/visit fractions identify an observed difference; tied rates use the control as a neutral starting point. Payments are retained historically even after refunds, with refund totals alongside them; a higher payment rate alone does not establish better revenue, profitability or customer quality.

Review the evidence and explicitly confirm **Prepare editable follow-up**. It creates one native campaign draft from the selected pinned starting copy, omits media, resets the CTA to the selected local landing destination so it does not inherit an old tracking token, retains its review link in the receipt and leaves copy unapproved. It does not invent a new message: make the deliberate single change in the campaign editor, use the normal content workbench and Studio, create a new tracking link for the draft, approve the resulting version using that link and prepare a new comparison. Only the latest review, no older than seven days, can create a new draft. Repeated requests return the existing draft receipt. Updating a current campaign never rewrites the saved starting copy.

The daily playbook is now **`growth-daily-v3`**. It prompts review of the latest started comparison when it has no review or its last review is older than one day. This bounded prompt is not an exhaustive backlog audit. Existing inquiries, paid delivery, due follow-ups and expiring quotes retain priority. Up to five moves are still returned.

### Delegate and inspect reports

```text
/agent schedule sage 1440 /growth review SITE_ID COMPARISON_ID
```

Use the existing agent controls to pause/run this assignment. Grant `growth.review` in an explicit specialist capability list when necessary; existing saved roles are preserved and do not silently gain new grants. The assignment binds to **this growth page** and rereads it before execution. Current UUID reservations, instruction/source fingerprints, structured report schema, account-scoped journal and manager read-back apply. Existing assignments pinned to an older version of this page need fresh reviewed assignments after deployment; they must not silently adopt updated instructions. A completed worker report verifies execution of the review, not the quality of the campaign or a profitable experiment. No new scheduler, report store or report schema is introduced.

### Permissions, rollout and recovery

Website owner/delegated manager/marketer access and the marketing feature entitlement are rechecked by the service, including retries and follow-up creation. Cross-site campaigns, comparisons, reviews and draft IDs are rejected. Designers do not gain marketing access. Comparison inputs, creative snapshots, links and review evidence are retained; referenced campaigns cannot be removed through the model. Current campaign edits do not rewrite history. Changing the experiment setup requires a new comparison.

Deploy migration `20261116040000_add_campaign_performance_comparisons.rb` before exposing this feature, using the existing per-instance update process. The workforce/report migrations from the current base remain prerequisites. Retain comparison/review/draft tables when reverting code.

Structured log events are `lightek.growth.comparison_created`, `performance_reviewed` and `performance_draft_prepared`, containing actor/site/comparison/review/campaign IDs without copy, tracking tokens or customer information. Review the saved comparison, measured timestamp, source health, action receipt and structured worker report in the existing IT tools. For missing counts, verify placement link use, date/time zone, enabled state and attribution rather than assuming zero total traffic. For changed creative, prepare a fresh comparison; for stale reviews, measure again; for revoked access/package, resolve authorization before resubmitting. Publication remains governed by its own provider receipts and reconciliation controls.

Acceptance: `SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/campaign_performance_checks.rb` exercises native schema/models/services, scoped HTTP/CSRF, measured cohorts, immutable reviews, guarded drafts and current worker documentation/UUID/journal integration. The inherited host fixtures replace private engine authentication/records and provider IO. Full installed/private-engine boot, real user placement/link usage, deployed publication and business results remain separate acceptance.

## Search, backlinks and marketing decisions

Open **Dashboard → Business → Growth → Search & backlinks**. The website's verified Google Search Console property may be the HTTPS URL prefix or the exact-host domain property. In Vault, configure `growth-search-console-SITE_ID` for consumer `LightekGrowth::SearchConsole` and purpose `search_console_read`. Provide Google OAuth `client_id`, `client_secret`, and a `refresh_token` with the `https://www.googleapis.com/auth/webmasters.readonly` scope. The Google account needs access to the property. Refresh records up to 250 page/query pairs from 28 finalized days and can inspect one same-host HTTPS URL. Search Console returns limited rows. An inspection describes Google's indexed version of the page.

Import a paired source/target CSV or save an external prospect manually. Review sources yourself before marking a link verified or lost. The prospect's **Authorize Nevaeh to draft outreach** button creates an approved goal for the Marketing SME, which prepares the draft and records the approving operator. Follow it in Nevaeh Goals. Review it before using your usual outreach workflow. CSV imports treat unverified rows as reported and preserve verified and lost decisions.

Use these decisions when reviewing the daily Growth plan or handing work to the Marketing copilot:

| Evidence | Marketing decision |
| --- | --- |
| Search impressions with low click-through | Review title and description against the observed query, search position, and page intent. Compare later snapshots after indexing. |
| Credible partner, review or editorial mention | Identify the specific benefit to their readers and prepare a relevant outreach draft for review. |
| Existing leads or expiring quotes | Address the open sales opportunity before spending more on acquisition. |
| Visits with weak inquiry or payment evidence | Check the promise, offer, form and checkout. Change one variable and measure the next cohort. |
| Paid campaign opportunity | Document the audience, offer, conversion event, spend ceiling and stopping criteria. Use campaign tracking to compare verified purchases and refunds. |
| Repeat customers | Segment existing customers by demonstrated need and use consented channels for retention and follow-up. |

The daily plan cites recorded data. Preparing and authorizing marketing work uses the existing campaign, CMS and goal workflows for their supported actions.

## Delegate website design and publication

The website owner or platform operator opens **Growth → Website design & content → Nevaeh website delegation** and authorizes the Marketing SME for that website. The grant can be revoked there. The worker rechecks the grant, the operator's site access and the installed packages when it begins a change. A revoked or replaced grant blocks queued work tied to the prior grant.

**Assign a landing page to Nevaeh** creates a goal to design the page from the supplied offer and publish it. Use Nevaeh Goals to assign several related steps and check their receipts. A goal can consume a previous step's verified page ID and revision. Use the Marketing SME for these instructions:

| Command | Inputs and result |
| --- | --- |
| `/website inspect SITE_ID` | Lists site pages and the current appearance revision. Pass `{"page_id":123}` to inspect page content and its revision. |
| `/website compose SITE_ID {…}` | Supply `title`, `slug`, native `sections` and a boolean `published`. A section uses `block`, `data` and optional `anchor` or `style`. To edit a page, provide `page_id` and its current `revision`. Optional `search_title` and `description` set CMS search metadata. |
| `/website publication SITE_ID {…}` | Provide `page_id`, current `revision` and a boolean `published`. |
| `/website appearance SITE_ID {…}` | Provide the current appearance `revision` and a catalog `design` or installed `theme_id`. Optional `fonts` and `colors` use Design Studio token fields such as `font_heading` and `color_primary`. |
| `/website restore SITE_ID {…}` | Pass the `page_id`, `revision` and `change_id` from the latest matching page-change receipt to restore its saved prior content. For a new page, use publication to take it offline. |

Website edits use the native CMS and Site Design library. A completed write receipt identifies the site, operator, operation and saved result. A page edit keeps a prior source for recovery. Existing page and appearance revision checks protect newer human edits.

## Write and publish Journal articles

Website delegation also gives the Marketing SME access to **Journal & Articles**. Choose **Assign an article to Nevaeh**, enter the title and facts, and choose a private draft or publication. Nevaeh uses the existing writing engine to compose from the brief and the Journal editor to save the article. Published entries appear on the website and its connected PWA. Follow the result in Nevaeh Goals.

Use `/website journal_inspect SITE_ID` to list recent articles, or pass `{"entry_id":123}` to read one article and its revision. Use `/website journal_write SITE_ID {…}` with `title` and either `content` or a `brief` with `facts` and optional `call_to_action`. Optional fields include `slug`, `excerpt`, `category` and `status`. To update, publish or archive an existing article, supply its `entry_id` and current `revision` along with the changed fields. Use `draft`, `published` or `archived` for status. New entries default to draft. Existing stories keep their URL and any attached images.

### Run the editorial schedule

In **Journal & Articles → Nevaeh editorial schedule**, enter the topics to follow and the exact public HTTPS pages you approve for research. Set daily or weekly and choose private drafts or automatic publication. The first cycle is due after saving. Nevaeh rereads the approved pages, selects an unused excerpt relevant to a topic, and writes a short Journal update with a source link. The cycle stops without publishing if there is no new, relevant source material. Source redirects require approving the final URL. Pause the schedule to stop subsequent work, including queued writes that have yet to start.

Every cycle has a goal that records research evidence before the article is written. For automatic publication, select **Prepare a social campaign draft** to add a promotion with the article's link. Review the generated copy in Content review, then use the existing social account and publication calendar. Provider media requirements still apply. Readers of the live article can share to Facebook, LinkedIn, X or email directly.

### Public relations

Open **Journal & Articles → Public relations** to assign a press release from an announcement summary, confirmed facts and a public press contact. Choose a private draft or publish under the existing website delegation. Published releases appear in the Journal under **Press Releases** and on the Lightek Media press page for the current site.

After publication, select the release, enter a media contact and explain why the story fits their audience. Nevaeh drafts a tailored pitch linked to the public release. Review the saved draft and open it in your email app when it is ready to send. Drafting does not contact the outlet.

The Marketing SME can use `/website press_release SITE_ID {…}` with `title`, `summary`, `facts`, `press_email` and optional `status`. Use `/website media_pitch SITE_ID {…}` with a published press release's `entry_id`, `outlet`, `angle` and `recipient`. The same steps can be assigned in a goal, using the first step's confirmed entry ID for the pitch.
