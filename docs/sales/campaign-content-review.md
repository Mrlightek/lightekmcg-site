# Campaign content variations, review and focused Studio production

## Business workflow

Open **Campaigns**, edit a campaign, and choose **Content variations & approval**. The website owner/managed operator and delegated managers/marketers can use the workbench. Designers do not gain campaign authoring or publishing authority. The marketing package feature and existing mailbox, Studio and publishing permissions still apply.

1. Complete the website's business growth brief in **Growth**. Keep the offer, audience, problem and value proposition factual and concise.
2. Choose an enabled tracking link for this campaign, or explicitly use its current CTA URL. The current URL is not automatically tracked; ordinary UTM text does not create first-party attribution.
3. Select **Prepare content variations**. The existing Nevaeh WritingEngine composes three editable approaches: offer, problem and benefit. This release uses its authored rules provider with the brief as context; no external AI request or arbitrary model-generated command executes.
4. Read the copy and writing-context evidence. Review tone, claims, length, channel, recipient/sender context, media and CTA. Supported voice directives include `Tone: direct`, `Tone: warm`, `Max words: 100`, `Opening: ...` and `Closing: ...`; unsupported direction is reported rather than silently claimed as understood. Provider-specific length/media limits remain the existing provider adapters' responsibility.
5. Save edits before approving. The approval form explicitly approves the **saved revision**, not text currently unsaved in another form. Stale revision submissions are rejected.
6. Confirm review and select **Approve & use this version**. The saved copy is applied to the campaign and its status becomes Ready. Approval records actor/time and a fingerprint of the applied payload. The approved variant becomes immutable. This action does not send email, publish social media, generate/render media or spend money.
7. Create/open the campaign's Studio production, finish the media, and use the existing authorized publishing or audience-sending tools. Setting a new media URL changes the approved payload; prepare/review a fresh set before sending it.

Repeated generation requests with the same request key reuse the three drafts. Retrying approval reuses the same approval only while it still matches the campaign. Another variation from an old baseline cannot overwrite the applied copy; generate a fresh set when the campaign or business brief changes. Draft edits have optimistic revision counters and diagnostic logs; this is not full text history for every draft keystroke. Approved text and its original business context are retained.

The page shows the latest 30 variations. Campaigns with tracking or content-review history cannot be deleted; mark them completed and disable links instead. A campaign that already has delivery/publication records requires a separate campaign for new approved copy, preserving provider idempotency and historical receipts.

## A social campaign is a focused use of Studio

The campaign defines the offer, audience, business goal, call to action and production format. Studio remains the editing and production engine.

| Social format | New Studio timeline |
| --- | --- |
| Portrait short / story | 1080 × 1920, 30 fps |
| Square social video | 1080 × 1080, 30 fps |
| Landscape promo | 1920 × 1080, 30 fps |

Choose the social format in the campaign editor. Non-social campaigns retain the existing landscape handoff. Format selection is part of the content fingerprint. These formats configure production dimensions, not a guarantee that every social provider accepts every output.

The existing project creation request reopens one production per campaign/collaborator. A new production receives the campaign copy as its editable script plus a production brief containing offer, audience, goal, CTA, destination, effective format and content fingerprint. If the payload is approved through this workbench, business context comes from that approval's frozen brief; a later growth-brief edit does not silently change its audience.

Reopening preserves script, timeline and media edits. If the campaign fingerprint differs from the production's source, the controller reports that difference. **Replace Studio script with current campaign copy** is a separate confirmed action: it replaces only the script and source-brief metadata while preserving timeline/media edits. Existing timelines do not automatically resize when the campaign's selected format changes; change dimensions intentionally in Studio or use a separate production/campaign.

This is a focused route into the existing full editor, not another media engine. It does not automatically create a finished video, assign platform accounts, sync a render into `media_url`, or publish an edited production. Media creation, export selection and provider readiness remain their established workflows.

## Approval and queued execution

Approving a variation enrolls that campaign in version-specific review (`content_review_required`). Campaigns that have not adopted this workflow retain their existing Ready behavior; this release does not retroactively certify or require new approvals for all legacy campaigns. The form cannot disable review for an enrolled campaign.

The SHA-256 fingerprint covers channel, production format, headline, message, CTA label/URL, media URL, sender mailbox and recipient. Changing those fields clears the campaign approval and returns a Ready campaign to Draft. Renaming a campaign or changing its sending window does not change its content fingerprint. Campaign edits also require the current optimistic lock version.

The current authorized manager/marketer may review their own draft; this is attributable review, not independent two-person approval. Content approval does not grant provider-credential management or additional publication rights.

- SocialDispatch holds the campaign lock while checking approval and submitting the payload through its existing provider flow. A changed or unapproved enrolled campaign is blocked before provider IO. Unknown provider outcomes still require the existing reconciliation path.
- Single-email delivery checks approval inside its existing campaign lock.
- Audience queue creation snapshots the approved digest into each delivery row. The delivery worker rechecks current approval and digest while holding the campaign lock. A mismatch records a failed delivery and diagnostic event; it cannot silently send revised copy under an older request.
- Newly scheduled email jobs carry their expected digest. A stale enrolled job without a digest, or one whose payload changed, does not send. The audience service checks the expected digest again under the campaign lock, closing the gap between the scheduled job's initial read and queue creation. Review and schedule the intended version again.
- Existing subscription/unsubscription checks, sender readiness, Mail submission idempotency, provider confirmations and payment/delivery evidence remain authoritative.

A Studio edit is separate from the campaign's approved media URL: approval does not automatically attest to later changes in an independently edited Studio scene or externally hosted media bytes. Review the final exported asset and update/reapprove the campaign payload before publication. The fingerprint binds saved fields/URLs, not a cryptographic snapshot of externally hosted media content.

## IT operation

Deploy `20261115160000_add_campaign_content_review` on each client instance through the existing update pipeline. It adds campaign review/format/lock fields, content variants and the queued-delivery digest. It does not alter existing customer payment, provider credential or Studio runtime configuration.

Structured events use `lightek.growth.content_generated`, `content_edited`, `content_approved`, `delivery_content_changed` and `schedule_content_changed`. They include site, actor, campaign/variant/delivery IDs and applicable fingerprints, not copy, brief contents, customer addresses or credentials. Read the native workbench, campaign state, delivery error and existing system logs to troubleshoot. Database approval records and provider receipts are authoritative.

For a blocked action, check site/marketer access, the marketing feature, current draft lock version, growth-brief revision, campaign baseline and enabled tracking selection. Generate a fresh set for changed source data. For existing delivery/publication history, create a separate campaign; do not mutate the old provider request into a new payload. For stale queued work, inspect the stored digest/error and prepare a deliberately scheduled new campaign/version as applicable.

Retain history tables and review fields when reverting application code. Pause or drain newly version-bound scheduled jobs before reverting to older worker code that does not accept the digest argument. This release does not establish full private-engine or live provider acceptance on each instance.

## Acceptance

`ruby test/standalone/campaign_content_checks.rb` extends the existing daily-growth/CRM host with the production migration, shared writer, workbench, native routes/controller/view, approval invalidation and actual social/email scheduling guards. Coverage includes retry safety, saved-revision approval, stale sources, revoked/foreign access, disabled tracking, history retention, queued payload changes, optimistic editor writes and focused Studio source preservation/replacement.

The private authentication/package shell, social provider responses, Mail account readiness and Studio project allocation are boundary fixtures. StudioProduction's actual handoff logic executes against a saved scene fixture; this is not a full render or a live social publication.

Export native pages with `SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/publication_calendar_checks.rb`, then run `SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs`. Twelve controller-rendered screens are checked at desktop/tablet/phone widths, including the content workbench's draft forms, saved approval and Studio link.

## Final export and scheduled publication

The [Publishing calendar](publishing-calendar.md) now attaches a completed Studio export to a social campaign through a retained, issuing-host media link. Attach first, then review and approve the final payload. Supported accounts can schedule that exact version with current operator checks and separate provider-submission/publication evidence. Existing adapter limits and live verification still apply.
