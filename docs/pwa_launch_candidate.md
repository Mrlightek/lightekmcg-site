# PWA launch candidate acceptance and operations

Updated November 17, 2026. This is an implementation and acceptance runbook, not a production launch receipt.

## Current decision

The complete agreed offer is **not a launch candidate yet**. Three implementation blockers remain: automatic free member backend allocation, verified Free → Paid instance migration/cutover/rollback, and finalized YouTube cash settlement through a funded creator payout rail. `LightekPwa::LaunchReadiness` records these gaps and blocks new paid instance sales even if an old configuration flag is enabled. Existing verified paid periods, their cancellation and their historical revenue eligibility remain intact.

The new creator-support and YouTube publishing paths are implemented and covered by isolated database/API tests. They still require deployment, native-host CI, real account configuration and production acceptance. Never describe a local test double as a successful payment, cloud migration, channel upload or bank payout.

## Deploy and inspect

1. Run the repository's ordinary deployment/migration process. New migrations are `20261117110000` (creator offers/payments/earnings) and `20261117113000` (durable YouTube uploads). Preserve existing migration history; do not rename applied migrations.
2. Load the application with `bin/rails zeitwerk:check`. Run the native PostgreSQL/private-engine suite. A missing private-dependency GitHub App key is a CI configuration blocker, not a passing native test.
3. Run `LIGHTEK_VERIFY_HOST=lightekmcg.com bin/rails lightek_pwa:verify_infrastructure` using the existing infrastructure smoke checks, and `LIGHTEK_VERIFY_HOST=lightekmcg.com bin/rails lightek_pwa:launch_readiness` for the current implementation/configuration gaps. The latter exits nonzero while launch is blocked.
4. Visit PWA Administration → Memberships & YouTube revenue. Review readiness, upload operations, verified creator earnings and Nevaeh's source build. Configuration flags indicate selection/enablement, not completed external acceptance.
5. Keep all new feature switches closed until their own acceptance succeeds. Do not enable the complete paid-instance offer while the three implementation gaps remain.

## Creator subscriptions, gifts and tips

Central installation only: `LIGHTEK_CREATOR_SUPPORT_ENABLED=true` opens offer setup and support checkout. `LIGHTEK_CREATOR_PAYOUTS_ENABLED=true` opens release of confirmed available principal. The central site's tenant must be the platform owner. Default network fee is zero; optional `LIGHTEK_CREATOR_NETWORK_FEE_CENTS` must be 0–500. Existing commerce processing-reserve settings determine the separately quoted supporter fee.

A creator opens More → Creator earnings & support, sets a monthly price and enables support. Every free or paid creator keeps **100%** of tip, gift and subscription principal. A supporter sees principal, support fees, subtotal, renewal terms and applicable-tax notice before secure checkout. These are monthly financial-support subscriptions; this change does not add subscriber-only post/media access.

Only the signed canonical commerce checkout/invoice settlement creates a creator earning. A checkout redirect, pending order or client click cannot create a paid gift. A live gift requires the creator's currently live Studio project, matching site and public post. Public gift receipts show the supporter's profile name, disclosed before payment. Refund/dispute holds are excluded from the gift display.

The existing signed commerce webhook must include its checkout, invoice and subscription events plus `charge.refunded`, `charge.dispute.created` and `charge.dispute.closed`. Keep signature verification enabled. Do not create a second unsigned creator webhook.

Supporters can resume pending checkout from payment history and cancel monthly renewal even when payment is past due or the creator has disabled new support. A canceled checkout is not a paid subscription. An expired unpaid order is reconciled by the existing expiry job. Renewal receipts retain the original creator/principal/fee snapshot. Unusual credits, partial/multi-payment invoices or changed renewal totals require review and never manufacture principal earnings.

Before release, retrieve the actual payment source and balance transaction. Pending funds, an insufficient net charge, any refund/dispute, an unverified payout account or a changed in-flight destination block release. The transfer is exactly the full principal, bound to that charge and a stable idempotency key. A persisted `transfer_pending` intent survives a lost HTTP response; retry against the same account/key. Do not switch destinations to escape uncertainty.

`transferred` means credited to the verified payout account. It does not mean `bank_paid`. Use existing secure payout-account setup at `/dashboard/susu/payout-account`; bank details remain with the existing payment rail. Partial refunds/disputes hold the earning and attempt an idempotent full reversal of its own transfer; do not fund it from another creator. A failed reversal requires operator reconciliation. No automated YouTube estimate payout is introduced.

Acceptance: use two ordinary accounts. Test a tip, a live gift and a monthly subscription; inspect the signed receipt, exact principal, fee disclosure, duplicate-event handling, cancellation, failed payment, refund and account-scoped earnings. Verify a real account credit and subsequent external bank delivery separately. This work did not charge anyone or move production funds.

## Central YouTube publishing

Central infrastructure stores OAuth `client_id`, `client_secret` and `refresh_token` in Vault. Allow consumer `LightekPwa::YoutubeApi`, purpose `youtube_publishing`. Configure `LIGHTEK_YOUTUBE_CREDENTIAL_SLUG`, the exact `LIGHTEK_YOUTUBE_CHANNEL_ID`, and `LIGHTEK_YOUTUBE_UPLOADS_ENABLED=true` on the central installation only. Do not copy these credentials to a member instance. Default channel admission is 20 uploads in a rolling day and 10 per creator; `LIGHTEK_YOUTUBE_DAILY_UPLOAD_LIMIT` is configurable and must fit actual channel quota/capacity.

The author first uploads one original to their own current source application and creates a public video/clip, then chooses Publish to YouTube, confirms redistribution rights and accurately selects the children's audience. Other users cannot authorize that video. Private, restricted, community-only, reply, expired, hidden, missing-original or multiple-original submissions are rejected. Sharing an existing YouTube URL remains a separate embed action and does not establish channel ownership or attributable revenue.

Local central posts read their own original. Connected paid instances send an authenticated source identity and expiring original-only grant through the existing federation connection. Central derives the source hostname from the verified order, pins transfer to its managed server address, follows no redirects, limits bytes and checks the original checksum. Temporary central staging is purged after public processing; the member's original remains. This is not a claim that free-instance allocation/federation is complete.

The worker verifies the actual authorized channel, creates a resumable session and stores its sensitive session URL in Vault before sending bytes. PostgreSQL session locking spans network requests without rolling back durable receipts on a lost response. Each attempt probes the same session first. An expired/unknown session requires reconciliation; never start a replacement blindly. Find the publication UUID in the channel video's description if manual channel reconciliation is required.

An uploaded video is not playable yet. Only a provider receipt showing processed, public and embeddable activates its YouTube ID in the source PWA. Pending submissions show a processing placeholder. Legacy native videos remain compatible; not every historical video has been submitted. API/project/channel restrictions can prevent public embedding. Verify actual returned status; do not infer success from an upload request or promise ad eligibility from upload success.

Authors can request channel removal. Making the source private/hidden/restricted or deleting it queues withdrawal, retaining a durable operation after source deletion. A late upload/processing response cannot overwrite withdrawal intent. The worker deletes the known channel video and confirms deletion before `withdrawn`. An expired uncertain session requires channel review. Original retention and source-post removal are distinct operations. Operators inspect pending/reconciliation states in the revenue panel.

`CommercialRecoveryJob` runs every five minutes for bounded recovery of lost enqueues and pending settlement/uploads. Pending uploads also enqueue their next bounded continuation. Confirm scheduled jobs and queue consumers are active in production. A ready video is not evidence of channel monetization/YPP eligibility.

Acceptance: connect the actual channel, publish one owned original from each supported source path, inspect the upload receipt, public processed state and PWA playback, interrupt/recover an upload, and confirm withdrawal. Production OAuth/channel acceptance was not performed here.

## Business activation

After a verified active Business purchase, the member becomes their own white-label agency with an agency profile, under the existing upstream account relationship. No role changes occur at checkout creation or return. Existing branding/upstream agreements are preserved. Staff/directory roles cannot be converted through this path, and payment never grants super-administrator powers. This does not remove the full paid-offer launch gate or provide unlimited client servers.

## Remaining allocation and migration implementation

Reserve a capacity-bounded lightweight member application at signup, preserving a stable member identity/hostname. Do not spin up an unbounded full database/worker stack per free signup on the small shared host. Enforce isolation, upload/storage/mail quotas and global admission limits.

For upgrade, persist an operation, freeze source writes briefly for the final delta, copy only that application's data and attachment objects, verify hashes/counts and owner access, prove publication/identity continuity, switch the stable route and verify rollback. Keep mail on the mail cluster unless a separate mail move is explicitly required. Never provision an empty replacement and label it a migrated account. Existing central posts remain a checkout blocker until this is implemented.

## Remaining view-earnings settlement implementation

The underlying paid-creator contract remains 80% of attributable channel proceeds after YouTube's share. Lead UX with reported views, estimated earnings and calculated earnings per 1,000 views. Sharing starts on the first complete Pacific reporting day inside verified historical paid periods; free periods do not become retrospectively eligible.

Finalize the whole-channel statement, allocate adjustments using the documented channel-wide denominator, retain source evidence and verify received funds. Fund the actual outgoing payment rail, bind allocations to that funding receipt, prevent duplicate allocations and retain holds/reversals. Imported estimates and AdSense bank receipts are not automatically available processor funds. This implementation remains missing, so the paid offer requiring view payouts at launch stays closed.

## Final launch acceptance

Complete ordinary-user signup → confirmation → backend ready → first post → reply/message → return visit. Test desktop, mobile, keyboard, readable contrast and installed/offline-shell behavior. Verify real branded mail send/receive and spam controls. Publish launch programming, clips, welcome posts and two or three actively hosted communities.

Only then record a production launch decision against the deployed source revision and actual receipts. Training data preparation, local tests and a green deploy alone are insufficient.
