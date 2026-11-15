# Sales & CRM

Open **Dashboard → Sales & CRM**, or **Business → Sales & CRM**, and choose the business website. The shared Business workspace also includes a Sales tab. Each website has its own companies, leads, deals, routing and activity history.

This workspace helps an owner run a repeatable sales process: capture interest, understand the buyer, agree on a next step, qualify the opportunity, prepare a proposal and follow the deal through a decision.

Website form intake, reviewed CSV imports and assigned follow-up tasks are available in [Inquiry intake and sales follow-through](intake-and-follow-through.md).

## Start with your own business

1. Choose the website you sell through. For Lightek itself, use the Lightek business website rather than a client website.
2. Choose **New lead**. Enter the person's name, email, company and source, such as `referral`, `website` or `event`.
3. Give the lead a concrete **Next step** and **Follow-up date**. For example: “Call Jamie Tuesday to confirm the website scope and budget.”
4. After speaking with the prospect, open the lead and log a call or meeting. Capture the need, budget, decision maker and timing in Notes. Move the status from New to Contacted, then Qualified when there is a real opportunity.
5. Save the Qualified status, then use **Convert qualified lead**. Enter the deal name, total expected value, currency and expected close date.
6. Work the deal through Discovery, Qualified, Proposal and Negotiation. Each stage includes guidance for the next conversation. Close as Won when the sale is agreed, or Lost with a reason.
7. For a won deal, complete the order, payment and onboarding through existing Commerce workflows. A sales status does not create an order, collect money or record accounting revenue.
8. Review **Today** regularly. It shows due follow-ups, overdue expected close dates and active leads/deals missing a next step or follow-up date.

For a person buying without a formal company, use a clear relationship/account label that you can recognize. A company record represents a sales relationship; it does not create a platform user, managed client or server installation.

## Companies and contacts

Create and edit company accounts under **Companies**. Their detail pages show associated people and deals, with shortcuts to add either. Deal pages link back to their company and contact.

**Contacts** extends the existing Marketing contact records instead of creating a second email directory. Contacts include name, phone, job title, company, sales owner and relationship notes. For existing Commerce-authorized owners, the contact page links to purchase history using the existing customer-email lookup.

- Contact email is normalized and unique within a website. Existing addresses are read-only in Sales so a different person cannot inherit the address's consent history.
- Creating or converting a sales lead never subscribes the person to campaigns. Existing subscription and unsubscribe timestamps remain intact.
- Conversion matches companies by trimmed, case-insensitive name and contacts by normalized email. If the contact already has a company, that company is retained. Conversion does not overwrite a known contact's name or phone.
- A contact with linked deals cannot be moved to a different company. Deal contacts must belong to the deal's selected company and website.
- Repeating a completed conversion returns its existing deal. Failed conversion rolls back the company/contact/deal writes. Converted leads remain visible, with a link to the active deal.

## Owners and lead routing

The website owner and explicitly delegated **Manager** or **Marketer** members can work sales. Eligible employee accounts can participate through those memberships; employment alone grants no access. Designer-only membership does not grant CRM access. Agency/super-admin visibility follows existing website ownership rules.

Website owners and authorized account managers can configure **Lead routing**. Each rule maps one exact source, ignoring case and surrounding whitespace, to an eligible owner. Edit the source or assignee to change a rule.

For a new lead without an explicit owner:

1. Use the matching source rule if its assignee still has sales access.
2. Otherwise assign the eligible person entering the lead.
3. Otherwise use the eligible website owner, or leave it unassigned if none exists.

An explicit owner takes precedence. Changing a routing rule does not reassign existing leads. Revoked memberships cannot receive newly routed leads. Sales access does not grant infrastructure, directory administration or membership-management authority. CRM follows the installed **Commerce** package feature, including its existing write-metering rules.

## Pipeline and forecast

The pipeline groups deals by stage. Filter by sales owner or deal name. Each deal records amount, currency, probability, forecast category, expected close date, next action and follow-up date.

Default stage probabilities are Discovery 10%, Qualified 30%, Proposal 60%, Negotiation 80%, Won 100% and Lost 0%. Changing an open stage updates its default probability unless probability is also changed. Won and Lost always use 100% and 0%. Reopening a deal clears its closed timestamp. Losing a deal requires a loss reason.

Choose the forecast month and owner, then **Apply**. Search filters also constrain the forecast to matching deals. Amounts are shown independently for USD, CAD, EUR, GBP and AUD; there is no exchange-rate conversion or combined currency total.

| Forecast column | Meaning |
| --- | --- |
| Open pipeline | Full value of open deals expected to close that month, excluding Omitted |
| Weighted | Sum of each included open deal's value × probability, rounded once to cents |
| Commit | Included open deals explicitly categorized Commit |
| Best case | Included open deals categorized Best case or Commit |
| Won / Lost | Full deal values in those stages with expected close dates in the selected month |

These are user-entered sales estimates, not a predictive model or a statement of collected revenue. A close-date change moves the deal to the corresponding forecast month. Historical forecast snapshots, quotas and manager adjustments are future work.

## Activity, recovery and current limits

Save a note, call, meeting or email activity on a record. The timeline records actor and time, plus creation, edit and conversion events. Logging an Email records a conversation; it does not send a message. Activities are not editable through this workspace. Record edits require the current version; a stale save asks the user to reopen and review the latest record.

Disqualify inactive leads or close lost deals with a reason. This release does not offer destructive CRM deletion. Lists show up to 200 records, pipeline columns up to 40 deals each, follow-up lists up to 100 of each type, related lists up to 50 of each type, and activity timelines up to 100 entries. Use owner/name filters to narrow large lists. The forecast covers the entire filtered scope, including records beyond visible list limits.

Opt-in published-form intake, reviewed CSV staging and in-app due tasks/calendar downloads are now delivered in the follow-through sprint. Contact merging, custom stages, round-robin/territory routing, email reminder delivery, email/calendar synchronization, quote approval, automatic order handoff and typed Nevaeh sales commands remain subsequent work. There are no external AI calls or automatic customer messages here.

## CRM completion sequence

| Sprint | Business outcome | Acceptance |
| --- | --- | --- |
| 1 — Sales foundation (this release) | Capture → qualify → convert → manage deals and follow-ups → estimate pipeline | Site-scoped records, shared contacts, source routing, atomic conversion, stage guidance, independent currency totals and activity history |
| 2 — Intake and follow-through (delivered core) | Inquiries enter the pipeline and the right person follows up | Opt-in published-form adapter, reviewed CSV intake, duplicate linking, assigned/snoozable due tasks, calendar snapshots, source attribution and queue recovery. Email/calendar synchronization remains separate work. |
| 3 — Quote to delivery | Agreed scope becomes an approved, payable and fulfilled service | Versioned quotes, approvals and signatures against verified existing Bank/Commerce contracts; traceable deal/order/invoice/payment/provisioning links; retry without duplicate billing |
| 4 — Team sales management | Managers can operate a growing sales team | Configurable stages, ownership queues, round-robin/territory rules, quotas, stage aging, conversion/loss reports and forecast history |
| 5 — Nevaeh sales execution | Natural-language requests execute supported sales workflows | Typed site-authorized capabilities, deterministic inputs, traceable receipts, escalation and tested recovery; external outreach uses the established communication permissions |

## Verification

```sh
ruby test/standalone/sales_intake_checks.rb
SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/sales_intake_checks.rb
SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs
```

The standalone suite runs the real migrations, models, transactional services, jobs, route file, controllers and native ERB views using Rails/ActiveRecord and SQLite. The private Dashboard authentication/layout and existing website-ownership resolver are fixture boundaries. Set `SALES_DATABASE_URL` to a disposable database to run the same contracts on another adapter; this script creates/deletes fixture tables and must never target production. Browser checks inspect the actual controller-rendered views inside a fixture Dashboard shell at 1440, 1024 and 390 pixels. Screenshots are optional with `SALES_SCREENSHOTS=1`; `CHROMIUM_PATH` can select an installed browser. Production MFA, package enforcement, PostgreSQL contention and client deployment acceptance remain host-environment verification. The Sales CRM acceptance workflow runs the standalone and browser checks on pull requests without private engine credentials.

Deployment requires `db:migrate`; the migration adds the CRM tables and enriches the existing Marketing contacts. Existing campaign permission fields are retained. No prospect data, example deals, routing assignments or customer messages are seeded automatically.
