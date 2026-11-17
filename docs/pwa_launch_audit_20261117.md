# Lightek PWA launch audit and monetization plan

Updated November 17, 2026, after merged PRs #312 and #313. Current follow-up: `feat/pwa-isolated-member-launch`, based on `develop` at `89cc4b79cbe40e87db3d8eb89d7f2fcf6179868f`. The new code has not been deployed. Earlier production observations below remain historical owner-session evidence.

## Launch decision

The follow-up implements the three previously missing services: capacity-bounded allocation on a **separate shared server**, a resumable native shared-to-dedicated backend migration, and finalized monthly view earnings with an API-verified funded transfer rail. The owner can configure these through PWA revenue administration. Free originals have no fallback onto the central server. New paid sales require the complete configuration plus explicit owner enablement; flags do not establish production verification.

Local database and boundary tests pass for these paths. Production/native acceptance is still required: authorized private-engine/PostgreSQL CI, a real separate-host signup/upgrade with original-media verification, billing/refund/settlement, central channel upload/playback/withdrawal, desktop/mobile journeys and external branded email. The previously inspected native CI job receives **Not Found** looking up the CI GitHub App installation on dependency owner `lightekmcg`; credentials were present. An authorized installation must be corrected rather than bypassing native tests. No real cloud allocation, payment, channel upload or bank payout is claimed by this follow-up.

## What works and what is missing

| Area | Evidence | Assessment |
|---|---|---|
| Home/feed | Live production page showed a real persisted post, author, timestamp and interaction controls | Read path works; sparse launch content. Successful mutations require ordinary-user acceptance. |
| Watch/Clips/Communities | Live routes loaded valid empty states | Functional empty reads. Publish real programming, clips and initial communities before promotion. |
| Messages | Live owner conversation list populated | Read path works. Two ordinary members must verify send/receive and notifications. |
| Money | Live account invoices and pending records loaded | Workspace reads work; no successful production charge or withdrawal was performed. |
| Studio/live | Live production Studio entry loaded persisted projects/scenes and controls | Existing production foundations; this audit did not verify every render/export/broadcast. |
| Social writes and media | Real SQLite/Rails/controller tests cover tenant/author boundaries, visibility, replies, uploads and ranges | Substantive local evidence. Native PostgreSQL and ordinary-user production acceptance remain separate. |
| Signup | Source implements password signup, CSRF, rate limiting, PWA return destination and existing MFA flow | Fresh ordinary production signup not performed. A committed setup request now drives allocation on the separate pool, with bounded capacity/recovery and one-use sign-in. |
| Install/offline | Manifest/icons/service worker exist; updated shell caches new commercial scripts | Offline shell only. No offline publication queue or offline YouTube download. Browser/iOS install acceptance pending. |
| Membership billing | Scoped recurring purchase, actual configured hosting price, verified active paid periods, cancellation and delivery status | Foundation exists. New sales require a ready separate host and all commercial configuration; native/deployed acceptance remains pending. |
| Free member backend | Separate native applications/databases/queues/storage on a remote shared pool, signup outbox, capacity/resource/storage controls | Implemented locally. No central fallback. Native profile shares a system user; per-member VM/container sandboxing is not claimed. Pilot/load acceptance pending. |
| Upgrade/migration | Native complete-backend snapshot, checked resumable chunks, counts/media hashes, stable central IDs/URL cutover and retained source | Implemented locally; target/source revisions must match. Restore before activation; after activation use a reverse transfer. Real host acceptance pending. Legacy central originals still require a scoped migration. |
| Central references | Authenticated peer revisions/outbox/tombstones; direct anonymous source reads | Public paid-peer references work in local tests. Central stores title/type/owner/source metadata, not remote body/media. Free content peers are now supported; central replies remain central. Full private cross-instance social federation is not claimed. |
| YouTube original upload | New author-consent, exact-channel verification, fixed-origin original retrieval, checksums, Vault session receipts, bounded resumable worker and processing state | Implemented and locally tested. Actual channel authorization, quota and a real remote/native-host upload remain unverified. |
| YouTube playback/removal | Source activates YouTube ID only after processed/public/embeddable receipt; pending placeholder; durable withdrawal and channel deletion | Locally tested, including lost response, late completion vs withdrawal and retained originals. Legacy native videos remain compatible; submitting an existing YouTube URL does not establish channel revenue ownership. |
| YouTube view estimates | Official normalized report imports, reported views, creator estimates/RPM and historical paid-window eligibility | Implemented and tested. Estimates are not cash. Whole-channel finalized monthly allocations and API-verified funding/transfer settlement are now separate implemented paths; actual account acceptance remains pending. |
| Creator subscriptions | Separate supporter → creator offer/payment relationship, immutable price/fee snapshots, signed recurring settlement, status, cancellation and pending-checkout resume | Implemented locally. Monthly financial support does not add subscriber-only post/media access. Real recurring payment acceptance pending. |
| Tips/live gifts | Server quotes disclose fees; verified payment creates earning; live operation must belong to public post author/site | Implemented locally. Only confirmed gifts appear, with disclosed public supporter names. In-player live UX and actual broadcast/payment journey require production/mobile acceptance. |
| Creator support payouts | Real source charge/available balance checks, full-principal transfer, held/available/pending/transferred/reversed states, stable destination/key, refund/dispute recovery | Implemented with real-service boundary tests. No production funds moved. Account credit and bank delivery remain distinct; YouTube estimates do not enter this rail. |
| Branded mail | Real scoped mailbox after signup-email confirmation; verified platform domain and explicit enablement; 250 MB / 20 daily recipients starting allowance | Existing tests pass. External SMTP send/receive, DNS/reputation, queues and capacity not accepted here. |
| Business/Agency | Existing client/reseller/feature controls plus new idempotent role/profile activation after verified active Business payment | No role at checkout/return and no super-admin grant. Each client server billed separately. New paid sales remain configuration-gated. |
| Nevaeh | Targeted source pack now includes current guide, audit and acceptance runbook; fingerprinted KB/learning integration | Local learning-plan checks pass. Updated material requires a fresh reviewed build. Production model training was not performed. No new executable contracts are invented by documentation. |

## UX changes and remaining acceptance

The earlier live home exposed eleven service links above a small feed and seven primary navigation destinations. The merged work reduced navigation to five primary destinations, grouped secondary tools under More, clarified Membership/My instance, retained PWA signup destinations and corrected misleading offline wording.

This follow-up adds Creator earnings & support under More and creator-support links on posts/live broadcasts. Supporters review the creator principal, additional support fees, subtotal, renewal terms and tax notice before checkout. Payment history distinguishes pending/canceled/paid and supports resuming an unpaid checkout. Cancellation remains reachable when a creator pauses support or a payment is past due. Creator earnings show holds and payout-account transfer status without claiming bank delivery.

Authors can explicitly authorize a saved original for central YouTube publishing, choose the children's audience, see upload/processing/reconciliation status and request withdrawal. The UI never treats a submitted upload as ready playback. Dashboard revenue administration shows implementation gaps, non-secret configuration flags, upload operations and verified creator earnings.

Remaining UX acceptance: signed-out visitor, ordinary free creator/supporter, paid member, agency and client on desktop/mobile; contrast, narrow-screen overflow, keyboard/focus/error recovery, checkout return, pending-payment resume, live gift experience, Studio/mail return paths, PWA install/offline shell. Client render/API contracts pass; visual acceptance of the newly deployed screens remains pending.

## Pricing and monetization strategy

| Tier | Agreed service | Pricing approach |
|---|---|---|
| Community | Free participation plus separate member application on remote shared member servers, off the central Lightek host; bounded branded mailbox | Free. Capacity-bounded allocation implemented; the owner funds a separate shared server before signup delivery. Free hosting is a real platform acquisition cost. |
| Personal | Move the same application to its own server; central discovery references continue | Target $9.99/month only if measured compute, storage/transfer, backups, mail, support, payment costs and margin fit. Actual configured hosting package controls the price. |
| Business / Agency | Own business backend, brand, client management, feature controls/resale; optional verified custom-domain mail | Approximately $29–49 is a hypothesis, not a configured promise. Each client server/package separately billed. |

$25 is a difficult entry price for social participation. The reason to charge is delivered infrastructure and business value. Market reference points from the earlier audit were US web X Premium at $8/month and Discord Nitro at $9.99/month; those do not demonstrate the cost of a dedicated Lightek backend. Recheck current prices before using them in external marketing.

Illustration only: $9.99 less a $0.68 payment reserve, $5 compute, $1 backup/network and $1 operations leaves $2.31 before other overhead/tax. At $10 compute the same offer loses money. Configured membership packages must pass the existing cost/margin/processing floor. Unlimited upload, generation or rendering is not included in a low social price.

Revenue order:

1. Creator support can bring creators and transactions while free and paid creators retain **100% of subscription, gift and tip principal**. Disclose supporter-side support fees; never silently take principal. Do not advertise a platform percentage as the creator's gift earnings.
2. Personal dedicated instances once allocation/migration/delivery pass acceptance.
3. Business/Agency account packages, separately billed client server resale margins and business mailbox capacity.
4. Central Lightek YouTube channel revenue, with paid-creator view earnings from the full paid launch. No revenue forecast without actual authorized channel reports and monetization eligibility.
5. Clearly labeled native community/original-program sponsorship. Do not place independent sponsorship overlays in the YouTube player.

Use the member headline **estimated earnings per 1,000 views**, calculated from that creator's own reported views and earnings. The underlying policy remains 80% of attributable channel proceeds after YouTube's own share to eligible paid creators, 20% to Lightek. Free-period view revenue stays with Lightek; free and paid creators retain all support principal. No fixed guaranteed per-view rate, artificial/incentivized views or retroactive free-period claim.

A $32 creator estimate across 10,000 reported views gives $3.20 per 1,000 views, as an example only. Estimates, finalized amounts, received funds, available payout funds, account transfers and bank delivery are separate states. Final channel adjustments need a documented whole-channel denominator. An AdSense bank deposit does not itself fund the payment processor's transfer balance. The finalized/funded model now retains monthly whole-channel evidence and verifies a separately funded payout balance. Live funding/transfer/bank acceptance remains outstanding.

## Allocation/migration acceptance still required

Preserve one member identity and stable hostname. Reserve capacity/destination and a durable operation, copy only the member application's data/configuration/attachments, verify hashes/counts/owner access and publication continuity, briefly freeze writes for the final delta, switch routing, verify real new reads/writes and rollback, and retain the old instance for a defined window. Keep mail on the mail cluster unless a distinct mail migration is requested. Cancellation/downgrade must preserve content and explicitly manage retention/quota/costs. Do not call an empty backend passing `/up` a migrated instance.

The current central-reference path is public syndication, not full private social federation. Search indexes titles/metadata; source full text is not centrally copied. Central moderation and source content ownership remain separate. Private cross-instance identity/follow/reply unification needs a separate contract.

## Launch and acquisition sequence

Before a full paid launch: fix native dependency CI access, configure the separate host and real accounts, deploy, and accept real billing/provision/migration, support payments/renewals/refunds/payouts, central YouTube upload/public playback/withdrawal, ordinary-member journeys and external email. Keep feature switches closed until their own acceptance succeeds.

Before invitations: publish an owned original program, three useful clips and a welcome post; create two or three focused communities with an owner and first conversation. The empty Watch/Clips/Communities experience is a content-acquisition blocker even when routes work.

First acquisition batch: personally invite 10–20 relevant people with a concrete reason to return, such as a live session, original show or useful community. Have five potential infrastructure/business customers try the complete paid flow after it is ready. This work sent no invitations, published no marketing and spent no money.

Suggested copy: “Your people. Your stories. Your own space. Join Lightek free—share, watch and build your community. Upgrade when you want a dedicated home for your content.” Explain server/migration terms on Membership, not in the first social welcome screen.

Measure signup → confirmation → backend ready → first post → first reply/message → return visit → support payment or paid checkout → verified settlement → delivered/migrated instance → renewal/cancel. Do not count checkout clicks as successful activation. A complete new acquisition funnel is not claimed by this work.

## Validation

| Check | Local result |
|---|---|
| PWA HTTP | 39 tests, 223 assertions, passing |
| PWA administration | 65 tests, 438 assertions, passing |
| Membership/reference/revenue | 12 tests, 55 assertions, passing |
| Creator support/settlement | 16 tests, 61 assertions, passing |
| YouTube source/resumable/withdrawal | 15 tests, 58 assertions, passing |
| Separate member allocation/tickets/migration | 11 tests, 48 assertions, passing |
| Finalized view reconciliation/funding/transfer | 7 tests, 32 assertions, passing |
| Backend archive/chunk/path/activation safety | 5 Python tests, passing |
| New commercial HTTP authorization/CSRF | 6 tests, 29 assertions, passing |
| Launch gate/Business activation | 4 tests, 16 assertions, passing |
| Branded mailbox suite | 12 tests, 62 assertions, passing |
| Existing commerce hosting | 40 tests, 127 assertions, passing |
| Targeted Nevaeh learning | 6 tests, 29 assertions, passing |
| Membership/remote-content/Nevaeh clients | 18 JavaScript tests, passing |
| New commercial UI contracts | 7 JavaScript tests, passing |

The old Studio test retried an idempotency key with a different title; the corrected test verifies identical retry and explicitly rejects changed input. The actual new navigation helpers/label are now loaded by the sidebar harness. Production code's changed-input protection was retained.

Processor/Google/cloud calls are explicit test boundaries. These are not native private-engine, real charge, real channel, real migrated instance, bank-delivery or visual acceptance results. See [the launch-candidate runbook](pwa_launch_candidate.md) for exact configuration and acceptance steps.

## Nevaeh learning

Prepare a fresh PWA knowledge/training build from the current policy guide, this audit and `docs/pwa_launch_candidate.md`. Review the source examples, choose an enabled internal model and run the existing sequential learning plan/checkpoint acceptance. Preparing batches does not establish updated model weights. Execution remains reference-only for undocumented/missing contracts; the source pack records outstanding execution gaps instead of inventing actions.

## Official references

- YouTube resumable upload protocol: https://developers.google.com/youtube/data/guides/using_resumable_upload_protocol
- YouTube video API/status and policies: https://developers.google.com/youtube/data/reference/rest/v3/videos and https://developers.google.com/youtube/terms/developer-policies
- YouTube channel reports: https://developers.google.com/youtube/analytics/channel_reports
- YouTube/AdSense finalization: https://support.google.com/youtube/answer/14728151
- Payment source-bound transfers and reversals: https://docs.stripe.com/connect/separate-charges-and-transfers
- Invoice-payment reconciliation: https://docs.stripe.com/api/invoice-payment/list
- Earlier market reference pages: https://help.x.com/en/using-x/x-premium and https://discord.com/blog/beginners-guide-to-nitro

New official funding references: https://docs.stripe.com/api/topups/retrieve and https://docs.stripe.com/api/transfers/create.
