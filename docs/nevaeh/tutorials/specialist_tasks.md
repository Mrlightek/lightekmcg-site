# Specialist operational reviews

## Run or schedule a review

Open **Workforce & goals**, select a specialist and choose its named task template. Replace the example website or employer ID with your actual account context. Delegate once, or open **Repeat on a schedule** and enter an interval of at least five minutes. Review results in **Reports & history**. Scheduling begins only after you submit the task.

Use **Guide & capabilities** to search by task name, inspect its fields and copy an editable example. Enter `/operations` to open this guide from chat. These commands run through the assigned specialist, Gatekeeper and Dispatch, then save the normal worker report and journal reference.

| Specialist | Task | Editable command |
| --- | --- | --- |
| Website Operator | Review open findings from the latest saved website audit | `/operations website {"site_id":1}` |
| Sales Coordinator | Find leads and open opportunities with follow-ups due today or earlier | `/operations sales {"site_id":1}` |
| Finance Operator | Find uncategorized transactions in authorized employer books | `/operations finance {"employer_id":1}` |
| Payroll Coordinator | Find draft payroll whose pay date is due | `/operations payroll {"employer_id":1}` |
| Commerce Operator | Find paid orders still awaiting fulfillment | `/operations commerce {"site_id":1}` |
| People Coordinator | Review open or access-revoked onboarding/offboarding cases | `/operations people {"employer_id":1}` |
| Hosting Operator | Find accessible servers with saved status other than healthy or decommissioned | `/operations hosting` |
| Compliance Coordinator | Find enabled monitors never checked, older than 24 hours, or carrying an error | `/operations compliance {"employer_id":1}` |

These reviews read actual saved records and report counts plus up to thirty record references per category. A completed review means the check ran; it does not mean every flagged issue was resolved. An empty website review without an audit explicitly reports missing coverage. Server checks use recorded status rather than a live network probe. Compliance source freshness does not establish legal compliance.

Domain permissions are checked before submission and again at execution. Employer reviews require the employer's people, payroll, accounting or compliance permission respectively. Website/sales reviews use the existing site membership and package policies. Commerce uses the website administrator scope; hosting uses accessible nodes. Reports omit personal contact information, financial amounts, bank credentials and server connection details.

The review tasks do not approve payroll, send payouts, change access, fulfill orders, deploy servers or apply website changes. Use each module's approval and execution workflow to act on findings. Paused/deleted specialists and customized scopes retain their restrictions. Existing default capability lists receive the corresponding review permission only if their lists are unchanged.

To schedule through a command, use the existing delegation form. For example, replace the employer ID below and explicitly submit it:

```text
/agent schedule payroll 1440 /operations payroll {"employer_id":1}
```

For a campaign, say **make me a funny tiktok campaign ad promoting Lightek & services**, or use `/campaign {"site_id":1,"service":"Lightek & services","tone":"funny"}`. Recognized campaign requests are delegated to Campaign Producer even when another chat specialist is selected. Explicit `/delegate` keeps the worker you name; an incompatible assignment remains blocked. Campaign production prepares an editable draft/private preview; it does not publish to TikTok automatically.

## Deployment

Apply migration `20261116040002_connect_nevaeh_specialist_reviews` before restarting Rails and workers. It adds the review permission once to unchanged default roles. It skips customized capability lists and deleted roles. Later directory reads never regrant a removed permission. Existing schedules are retained; new review schedules require explicit submission.

## Create a website page

Say **Create a website page called running_from_nevaeh_screen**. Nevaeh resolves an authorized website from the current page, request host or your single available website, then delegates to Website Operator. If several websites remain possible, choose one with `/website page {"site_id":1,"title":"running_from_nevaeh_screen"}`. The worker creates an unpublished draft, verifies its saved title and slug, and returns its page ID and the website pages management link. The title is preserved; underscores become hyphens in the URL slug. Existing slugs block creation rather than overwriting content. Publishing remains an explicit website action.

## Accounting & Billing operations

In Dashboard → Books & Accounting → Reports, an accounting administrator can schedule Nevaeh to apply saved categorization rules daily or weekly. She checks current employer permissions and authenticator enrollment before each run. Only uncategorized, unreconciled entries are eligible. Rules run in priority order and each applied category produces an audit event. The worker reports how many entries it categorized and how many eligible entries still need classification. Report and reviewed tax-reserve refreshes can run on their own schedules.

For account billing and support, see the [Billing SME](billing.md) and [Customer Service SME](customer_service.md) guides.

## Statement reconciliation and tax filing preparation

Open Books & Accounting → Reconcile, then select a complete committed statement and provide the opening and closing balances from that statement. Nevaeh matches the imported entries, proves both balances and finalizes the period with a receipt in Reports. A mismatch stops for review.

In Books & Accounting → Reports, schedule a Schedule C workpaper for the selected year. The worker checks the close date, category mappings and final bank reconciliations. An authorized reviewer can export the current workpaper for a preparer once its checks pass. Live IRS filing requires an enrolled, tested transmitter, complete return data and taxpayer authorization. The exported workpaper is a bookkeeping handoff.
