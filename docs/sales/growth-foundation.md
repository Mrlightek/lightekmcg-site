# Growth Foundation: campaign attention through delivery

## Start in Dashboard

Open **Growth** in the shared Business workspace navigation, or **Growth & attribution** from Sales & CRM. Choose the business website before editing. Owners, eligible managed-account operators, and delegated website managers/marketers can use this workspace; designers cannot. The marketing package feature must be enabled. Permissions are checked again when saving, including for previously opened tabs and cached workspaces.

1. Save the business growth brief: offering, audience, customer problem, value proposition, voice, goal and target date. The screen shows the last editor and revision. Reopen a stale tab before saving; it cannot overwrite another editor's revision.
2. Create a campaign under **Campaigns**, then return to Growth. Existing campaign and Studio production workflows remain the content authoring tools.
3. Create a tracked link with the campaign, placement label, source, medium and local destination path. For example, source `instagram`, medium `social`, placement `November profile link`, destination `/`.
4. Share the generated `https://<website-host>/g/<token>` URL on that channel. Each placement should have its own link. The destination must be a real page on this website; this release validates local-path syntax, not page existence. Use lowercase letters, digits, underscores or hyphens for source/medium.
5. When a visitor submits a published starter contact form, review it in **Sales → Inquiry inbox**. Accept the inquiry, qualify and convert its lead, issue a catalog quote, and record acceptance. Complete the existing payment and delivery workflow in Commerce.
6. Return to Growth to see which stages the campaign's tracked visits reached. Campaign source is also visible on the inquiry review, lead/deal, Dashboard quote and Commerce order screens.

The growth brief is authored business context, not automatic audience or competitor research. This sprint provides the measurements for future Nevaeh marketing playbooks; it does not implement an AI CMO, daily content factory, SEO crawler, account-reputation scoring or new social destinations.

## Attribution contract

- A tracked link is a random public placement identifier. It redirects only on its website's exact mapped host to an HTTPS path on that same host and adds `utm_source`, `utm_medium` and `utm_campaign=campaign-<id>`. External URLs, query strings, fragments, encoded separators and traversal paths are rejected. Ambient UTM parameters or user-submitted visit IDs do not establish attribution.
- The browser receives a signed, HTTP-only, SameSite=Lax first-party cookie containing an opaque visit token. Its attribution window is **30 days from the recorded visit**, without extending the window when reusing that visit. HTTPS requests set Secure. Reopening the same link in the same browser within 30 minutes reuses its visit; a different link or a later click records another visit and becomes the source for future submissions.
- HEAD requests, `DNT: 1` and `Sec-GPC: 1` do not create tracking visits. Capture also ignores an existing cookie when those privacy signals are present or marketing has been disabled. Missing, tampered, expired and foreign-site cookies produce unknown attribution. Cookies do not cross domains, instances, browsers or devices.
- A new inquiry stores its visit once. Intake transfers that visit only to a **new** lead. A repeat inquiry matching an existing lead retains its own source, but cannot relabel that lead or a preexisting deal. CSV and manual leads have no tracked-visit attribution unless supplied by trusted future capture code; operators cannot type in attribution through CRM forms.
- Lead conversion copies its recorded visit into the new deal. Quote acceptance copies the deal's visit into the new pending order. The customer quote link itself does not take credit away from the originating campaign. Direct native storefront checkout can copy a valid same-host visit without requiring a lead or quote.
- Attribution references are immutable through normal model writes and must point to an existing visit for the same website. Visit and link source/destination metadata are also immutable. Create another link for another destination/source. Disabling a link stops future redirects but does not erase visits or remove already captured attribution. Campaigns with tracking links cannot be deleted; mark them completed and disable the links.
- No historical attribution is inferred from email matches, CRM source labels, older orders or current browser cookies. Tracking starts after deployment. The existing sales routing `source` remains separate from the campaign's source/medium.

## Read the funnel correctly

The date filter selects a **visit cohort** using the application's timezone: visits first recorded between the selected dates, inclusive, up to 366 days. Each stage counts **distinct visit records** that have reached that stage as of the time of the report. Several inquiries, orders or processor notifications for one visit do not multiply its reached-stage count.

Stages: tracked visit, inquiry, lead, deal, order, confirmed payment, delivery recorded. These are observed milestones rather than a mandatory sequence: a direct storefront purchase can reach payment without an inquiry or deal. An existing lead's later inquiry can reach Inquiry for another visit without relabeling the original Lead. Link visits may include automated previews; counts are not verified people or complete website traffic. There is no JavaScript page-view SDK, cross-device identity graph, automatic bot exclusion or multi-touch attribution in this release.

Payment uses the existing persisted `paid_at` marker from commerce settlement, never a checkout redirect or a won-deal label. Delivery requires payment plus `fulfilled_at` or `provisioned_at`; it reports recorded completion, not an independent check that a customer used the service. Pending and canceled order records can still show that the Order milestone was reached.

The USD cards show the number of paid order records, their current confirmed totals, and separately recorded refunds for the cohort. Order totals can include tax and shipping. They are not profit, unique customer counts, bank settlement balances or net revenue. Fully refunded orders retain their historical payment milestone. Other currencies are not combined into USD.

**Unknown campaign source** uses separate record counts: inquiries/leads/deals created during the selected range and unattributed orders whose payment was confirmed during that range. These are activity counts, not members of the tracked visit cohort. Old records remain visible here. Do not add this panel to the visit-stage numbers or interpret it as direct/organic traffic.

## IT operation and recovery

The workspace includes link enable/disable actions, the brief editor/revision, cohort dates, recent attributed orders, payment/delivery state, links to Inquiry inbox/Sales/Commerce, and recovery instructions. There is no separate analytics provider to install. Apply `20261115140000_add_growth_foundation` on each independently installed client instance before exposing this release; run the existing migration/update pipeline.

Structured Rails log events use `lightek.growth.brief_saved`, `link_created`, `link_enabled`, `link_disabled`, `visit_recorded` and `attributed`. Events include site/actor/record IDs as applicable, not cookie tokens, form answers, brief content or customer email addresses. Normal application/system-log access remains permission-controlled. Database records and commerce receipts are authoritative; logging is diagnostic and does not substitute for transaction commit evidence.

If a campaign result is absent:

1. Check the link is enabled and uses the exact mapped website host. Check that its destination page exists and that the request reached this instance.
2. Confirm browser privacy preferences allow the cookie. Another domain/device, an expired window, or an ordinary untracked URL legitimately leaves source unknown.
3. Find the inquiry and review its campaign source. Accept it through Intake; enabling an intake rule affects future submissions and the existing recovery sweep remains available.
4. Check whether the inquiry matched an existing lead. Preserving that lead's original attribution is intentional.
5. Open the deal and its accepted quote, then inspect the linked order. Payment requires the existing verified processor settlement; delivery requires the existing fulfillment/provisioning completion.
6. Inspect the visit cohort dates. A later payment belongs to the earlier visit's cohort, not the date the payment arrived. Compare unknown-source activity separately.

To pause new capture for one placement, disable that link. For account-wide capture, disable the marketing feature through the existing package controls. Retain the migration tables and attribution references while records depend on them; reverting code should not erase measurement history. Existing queues, commerce provider credentials, public host/TLS configuration and starter forms still need their normal deployment readiness checks.

## Acceptance evidence

`ruby test/standalone/growth_foundation_checks.rb` executes the production migration, models, routes, services, public link and form controllers, native Growth view, lead conversion, quote acceptance/order placement, commerce processor-event settlement and fulfillment. The private Dashboard authentication shell, package account storage, remote checkout handoff, notifications, reservations and revenue-allocation boundaries are fixtures. This is not a live Stripe payment or a full private-engine boot.

Coverage includes first-party cookies, repeat clicks, duplicate inquiries/acceptance/payment events, source preservation, direct storefront checkout, unknown/expired/tampered/private capture, host/site and delegated-role rejection, stale brief updates, revoked access, local-path validation, campaign history retention, immutable attribution, refunds, cohort dates and bounded per-link report queries.

Export native pages with `SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/growth_foundation_checks.rb`, then run `SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs`. The browser check covers nine native screens at desktop, tablet and phone widths, including Growth's form controls, share URL and seven milestones. Private engine navigation/authentication and live provider behavior remain deployment acceptance items.
