# Website growth audits and guided CMS fixes

Open **Dashboard → Business → Website audit**, select an accessible business website and run a native audit. The audit reads published CMS pages through the installed native template renderer. It makes no outbound HTTP requests and runs no page scripts. It checks the output the CMS produces, rather than claiming to measure search rankings, traffic quality or conversion causality.

## Evidence and coverage

Each run saves its rules version, page coverage, findings and source fingerprints. Findings include missing or unusually long titles/descriptions, duplicate published page titles, missing/multiple main headings, image-description review, placeholder actions, generic native button labels, document anchors and links to unpublished/missing native CMS pages. The 70-character title and 170-character description thresholds are review heuristics, not search-engine requirements. Empty alt text can be appropriate for decorative images; dismissing a review prompt records that decision and its explanation.

Unsupported layouts, rendering failures and source limits appear as **unassessed**. Partial runs retain their assessed evidence. An empty findings list does not establish full coverage or a passing SEO score. External links, redirects, live HTTP delivery, script-generated content, app-store listings and accessibility conformance are outside this audit.

Bounded work per run:

| Boundary | Limit |
| --- | --- |
| Published pages | 50 |
| Stored findings | 200 |
| Sections / serialized source per page | 80 / 256 KB |
| Rendered HTML per page / total | 1 MB / 8 MB |
| Images / links inspected per page | 100 / 300 |
| Other published titles compared | 500 |

Limits stop or qualify coverage; they never silently produce a clean result. Reusing a request key returns the same run only for its original scope. Audit evidence is immutable. Later reviews and verification are recorded separately.

## Review, apply and recover

1. Expand **Evidence and source**. Review the page, source field and finding. Open Design & Content for findings requiring manual editing.
2. For supported fields, enter a proposed value and choose **Preview supported CMS change**. This saves a before/after preview without changing published content.
3. Review the changed field under **Review changes and recovery**, explicitly confirm it and apply. Application changes the current published CMS source, then runs a fresh page audit.
4. Read the verification receipt. **verified_absent** means that finding was absent in an assessed recheck; **finding_present** means it remains. Partial/unassessed or failed verification never establishes resolution. Use **Recheck current result** after repairing a rendering problem.
5. To recover, review and confirm **Roll back saved change & recheck**. Rollback is available only while the applied source fingerprint and values still match. Later manual edits are preserved by rejecting stale rollback requests.

Supported changes are dedicated title-tag/description metadata and registered native hero/split/image alt fields or hero/split/CTA/footer button labels/URLs where the registered block exposes that field. Metadata affects the actual public native layout without renaming the CMS page/navigation label. Values are escaped in output; button destinations are validated. Raw imported HTML, ambiguous matches, unregistered blocks and shared chrome owned by another page require manual CMS review.

Preview, apply and rollback recheck current authorization and source. A changed page, dismissed/resolved finding, outdated rules or changed preview version requires fresh review. Repeated successful apply/rollback requests return their existing receipt. A render failure after saving does not undo the committed CMS change: its receipt remains and verification reports unavailable/unassessed until a successful recheck. Rollback restores the prior field data or removes metadata created by that fix.

## Authority and IT operations

Read access follows existing site-scoped Sales/marketing access and the marketing feature entitlement. Guided CMS writes additionally require the existing **WebsiteIdentity CMS-owner scope** and design entitlement. A marketer or manager does not receive CMS ownership through this workspace. Review decisions require a reason and optimistic version check. Prepared changes do not grant ongoing access: revoked users cannot apply or roll back them.

Audit/finding/fix records preserve site, actor, time and review history. The displayed diff contains only the edited field; unrelated section data is not exposed in that preview. Structured log events are `lightek.growth.audit_fix_prepared`, `audit_fix_applied`, `audit_fix_rolled_back` and `audit_fix_checked`; correlate site, actor, fix and audit IDs. Logs exclude page HTML, proposed text and credentials. Error receipts retain error class for investigation. Page deletion removes its metadata while audit page IDs remain historical evidence.

Nevaeh's daily growth plan considers the latest **full-site** audit. Missing or older-than-seven-days evidence prompts a refresh; open findings or incomplete coverage prompt review. Page-only rechecks do not replace full-site coverage. Existing sales follow-up stays ahead of this recommendation. Recommendations never silently apply fixes or publish campaigns.

Deploy migration `20261115190000_add_website_growth_audits.rb` and the application update to each independent installation through the existing update pipeline. If a page cannot render, inspect its installed native template/catalog registration and source limits, correct the source/runtime issue, then rerun. A CMS edit after preview requires a new audit and preview rather than forcing an old change.

## Acceptance and boundaries

```sh
SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/campaign_performance_checks.rb
SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/website_audit_checks.rb --name '/test_site_|test_audit_/'
SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs
```

The CMS harness exercises real host rendering/templates, migration/models/controllers, metadata output, permissions, CSRF, limits, stale-source checks, immutable evidence, explicit apply/recheck/rollback and render failure recovery. Private engine shell/records and authentication boundaries are explicit fixtures. Browser checks exercise exported native views at 1440, 1024 and 390 pixels. Full installed Rails/private-engine boot, actual deployed HTTP behavior and search/marketing outcomes still require acceptance on the deployed installation.
