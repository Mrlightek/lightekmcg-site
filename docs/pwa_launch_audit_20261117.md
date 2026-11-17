# Lightek PWA: launch audit and monetization plan

Date: November 17, 2026. Source baseline: `develop` at `fd8c4ad`; production branch `main` at `be65999` was also refreshed. The user’s two migration renames and current schema from `main` are included unchanged in this branch. Live PWA inspected at `https://lightekmcg.com/lightek/index.html#/home` using the available signed-in owner session. Changes in this branch have not been deployed. This audit distinguishes live observations, isolated test results, source implementation and unverified production behavior. An owner session cannot establish the experience or permissions of a new ordinary member.

## Launch decision

The existing PWA has real social, messaging, media and Studio foundations. It is not yet ready to advertise the complete new offer of a free hosted member instance that seamlessly moves to a dedicated paid server. That automatic allocation/migration lifecycle does not currently exist. Payment-provider success, production server capacity, a real migrated instance and email send/receive must be verified before charging for that promise.

This branch supplies a tested implementation foundation for paid-instance checkout, central content references, YouTube embeds/reporting and branded member mailboxes. It is a draft, not an assertion that the entire launch is finished. Paid sales and branded mailbox issuance are closed by default. Existing central content blocks self-service paid checkout rather than silently provisioning an empty replacement. Newly added automated member-email confirmation is not an external SMTP acceptance test.

## What works, what is missing

| Area | Current evidence | Assessment / required work |
|---|---|---|
| Public PWA home | Live home loaded and showed a real persisted post, author, timestamp and interaction controls | Read path works. Very little launch content; control visibility does not prove successful mutations. |
| Watch and Clips | Both live pages loaded and reported no published content | Functional empty reads, not a populated streaming product. Publish real launch programming before promotion. |
| Communities | Live page loaded; no joined or discoverable communities were listed | Empty application, not a community acquisition experience yet. Create and moderate initial communities. |
| Messages | Live direct/group conversation list populated | Existing conversation reads work. Sending/receiving between ordinary new accounts was not tested live. |
| Money | Live account-specific invoices and pending transaction records loaded | Read workspace works. No successful payment, withdrawal or settlement was performed during this audit. |
| Studio | Live production entry loaded persisted scenes and creation controls | Entry point and project reads work. This audit did not execute paid exports, production renders or live broadcast delivery. |
| Signup | Source creates a client account/profile, uses password authentication, CSRF and rate limits | Fresh production signup was not executed. This branch keeps a PWA return destination and follows the existing MFA authentication lifecycle. |
| Social writes, audience rules, media reads | Isolated actual Rails database/controller/worker checks exercised site boundaries, public/private access, audience controls, replies, reactions, uploads and media ranges | Local evidence is substantive. PostgreSQL/private host integration and ordinary-user production acceptance remain separate. |
| Search and discovery | Existing read model searches real posts/profiles/communities | Central indexed metadata works. Remote full text search is not implemented; references index titles, not copied bodies. |
| Install/offline | Manifest, icons and service worker exist | Offline shell only. No offline publication queue, push-notification delivery or offline YouTube download was found. Browser/iOS installation acceptance remains pending. |
| Paid membership | No complete PWA paid-membership flow in baseline | Added plan display, scoped purchase records, canonical recurring checkout, active-period checks, cancellation and delivery status. Existing instance provisioner handles paid allocation after verified payment. No production purchase performed. |
| Free per-member shared instance | Existing Gatekeeper hosted-application service can add hostname-bound sites to a native Rails runtime | Automatic signup allocation, quotas/capacity reservation and member lifecycle are not connected. A site in a shared Rails/database runtime has logical tenant isolation; it is not a dedicated process or database. |
| Upgrade/move existing instance | No verified complete content/media/mail migration and routing cutover | Launch blocker for the newly agreed model. Account, profile, media and URL continuity must be tested. |
| Central feed with remote content | Baseline uses central content rows | Added authenticated peer reference sync, revision ordering, deletion tombstones, durable pending notifications and direct anonymous source reads. Central stores IDs/title/type/origin metadata; source body/media stay on the member instance. |
| YouTube playback/revenue | No complete PWA YouTube monetization/upload flow in baseline | Added validated embeds, reported views, earnings per 1,000 views and historical paid-period eligibility. Original video → member instance → central Lightek YouTube upload → YouTube PWA playback remains an implementation/launch blocker. No channel was connected or video uploaded during this audit. |
| YouTube upload automation | `ScreenplayEngine::SocialPublisher.post_to_youtube_shorts` builds metadata and prints success, without making an upload request | A simulated publisher must not be advertised as verified YouTube publishing. Separate from the new official embedded player. |
| Creator subscriptions/tips | No complete PWA supporter subscription/tipping flow found in reviewed source | Do not advertise it as ready. Preserve intended policy: creators retain principal; supporter processing/network fees must be disclosed before payment. |
| Member branded email | Baseline provisioning service assigned an address but mailbox creation was a placeholder | Replaced placeholder with real, account-scoped mailbox allocation after signup-email confirmation. 250 MB / 20 recipients daily starting allowance; issuing addresses requires an owner-verified brand domain and explicit enablement. |
| Business custom-domain email | Existing domain ownership TXT verification, mailbox records, quotas and mail controls | Available foundations. New free branded inbox alone does not grant custom-domain creation. Actual DNS, inbound delivery, outbound delivery and reputation require production verification. |
| Agency/reseller | Existing white-label accounts, client relationships, package controls and managed provisioning | Added Business / Agency to membership catalog; existing agency onboarding is required before Business checkout. Self-service agency activation is not complete in this branch. |
| Deployment health | Refreshed `main` has the user’s corrected migration names; `develop` retained the collision | Copied the exact two renames and schema already on `main` into this branch. Migration-version validation now passes. This is not a claim that production migrations or the new migrations were run. |

## UX findings and changes

The baseline home presents eleven service links above a very small feed; primary navigation also exposes seven destinations. Members must understand the platform's internal organization before seeing value. Watch, Clips and Communities have empty states but little reason to return. Studio opens a distinct full-screen workspace with a long scene list. Generic account signup could land a social member in the business dashboard. The offline toast implied automatic resumption despite no offline queue.

This branch adds a task-focused home introduction, groups secondary services behind a disclosure, keeps five configured primary destinations, preserves secondary destinations on More, and makes Membership / My instance a clear destination. Membership shows free signup, the actual configured package price, renewal terms, payment-confirmation status, instance-delivery progress and cancellation. PWA-origin signup retains the PWA destination. The offline message now asks the member to reconnect and retry.

Remaining UX acceptance: test unauthenticated signup, ordinary free member, paid member, Business/Agency and client roles on desktop and mobile; confirm no horizontal overflow, readable contrast, keyboard operation, clear error recovery and return paths from Studio/mail/instance sign-in. The new UI has render-contract tests; it has not yet had live browser acceptance after deployment.

## Agreed product structure

| Tier | Hosting model | Email | Commercial purpose |
|---|---|---|---|
| Free / Community | A lightweight, separately scoped member application on shared Lightek infrastructure | Lightek-branded mailbox, modest storage/sending allowance | Remove friction, build the community and brand; retain quotas and global capacity limits. Automatic member-instance allocation is still required. |
| Personal | Move the same application to a separately allocated server | Branded mailbox with a larger allowance once that upgrade is implemented | Sell capacity, control and reliability. Target $9.99/month only if measured costs permit. |
| Business / Agency | Own business backend with existing agency/client management | Optional mail on verified customer domains | White-label branding, clients and resale. Bill each client package separately; account subscription is not unlimited free servers. |

Keep creator/business infrastructure packages separate from social participation. A visitor should understand what is free and what the paid server provides without learning VPS terminology. Keep provider branding out of the member-facing experience.

### Pricing and margin

$25 is a difficult default entry price for a social membership. For context, X lists US web Premium at $8/month and Discord describes US Nitro at $9.99/month. Those are market reference points, not proof that a dedicated Lightek backend can profitably run at either price.

Recommend a $9.99 Personal target, a higher-capacity alternative if actual costs require it, and approximately $29–49 for a Business account as a pricing hypothesis. Do not publish those as fixed prices until a healthy configured package covers compute, backup, storage/transfer, mail, support, payment processing and central services. The implementation uses actual existing package prices rather than hardcoding an uncosted VPS offer. Its current managed-package provisioning path specifically validates Linode; a cheap quotation from another provider is not evidence that this provisioning path can use it.

Illustration only: at $9.99, a $0.68 processing reserve, $5 server cost, $1 backup/network allowance and $1 operating allowance leave $2.31 before other overhead/tax. At a $10 server cost the same offer loses money. Price unlimited upload/rendering separately; do not fund unbounded production CPU or egress from a small social subscription.

### Revenue sources, in launch order

1. Paid personal instances with verified provision/delivery and renewals.
2. Business/Agency account packages, client package resale margins and business mailbox capacity.
3. YouTube revenue from the central Lightek channel, with paid-creator view earnings included at launch and presented as estimated earnings per 1,000 reported views.
4. Clearly labeled sponsorship of native Lightek communities or original programming; never insert sponsorship overlays into YouTube's player.
5. Creator subscriptions, gifts and tips—including live gifts/tips—are launch requirements. Free and paid creators keep 100% of principal. Only disclosed supporter-side fees may cover processing/network costs. These complete collection/ledger/payout flows are not implemented by this branch.

No YouTube revenue should be forecast as earned until the Lightek channel’s official report exists. Embedding a third-party creator's video does not give Lightek its ad income. Official YouTube estimates and contractual creator shares must remain separate from received funds and withdrawable balances.

## Instance and reference architecture

Use one stable member identity and hostname across Free → Personal → Business. The central database remains the discovery/social index. A reference contains the owner identity, stable content ID, title/type and source URL; the owning application serves body/media. Avoid a central proxy for every media byte, which would recreate the bandwidth bottleneck.

On source changes, persist a notification before attempting network delivery. Central accepts only authenticated known peers, derives source origin and central author from the verified installation, and ignores repeated/older revisions. A deletion/private change removes the reference and retains a tombstone. Browser source reads are always anonymous, even if a source-domain session exists. Private/gender-limited content is not syndicated publicly. Source failure produces a per-post fallback instead of stopping the whole feed. Central moderation remains independent of the creator's source edits.

The added reference path currently supports paid registered peers. It does not yet connect free shared-host instances or all remotely published Studio/live formats. Source comments/reactions and central comments/reactions are separate records; fully unified cross-instance conversations/identity still need a contract. Private cross-instance feeds are not implemented. Do not represent public-reference support as complete social federation.

### Required Free → Paid migration acceptance

1. Reserve the destination and record a durable migration operation with source, destination, stable member ID and expected revision.
2. Copy only that member application's records, attachment objects and protected configuration. Do not copy another tenant or platform secrets. Keep mail on the mail cluster unless a separate mail move is required.
3. Check record counts, media hashes, owner access, PWA bootstrap, uploads, publication sync and service health on the destination.
4. Briefly stop source writes, copy the final delta, verify it, then switch the stable hostname/routing target. Keep identity and central reference URLs unchanged.
5. Test new writes/reads and rollback. Preserve the old instance for a defined retention window; do not delete it as part of payment confirmation.
6. Make cancellation/downgrade equally explicit: export/retention, shared-tier quota fit, data preservation and when the paid server stops incurring cost. Do not automatically destroy a member's data.

None of these steps is proven by a new empty instance passing `/up`. Automatic free allocation and this migration mechanism are the next implementation stage.

## Email as a brand and Business feature

A `member@lightekmcg.com` address reinforces the brand; Business can use `hello@their-domain.com`. Use a mail service with account-scoped mailboxes, not one mail daemon per free member. Member confirmation links bind to the signup email and current user. Brand-domain ownership remains with the platform; a member receives their mailbox, never administration of the brand domain. Custom-domain use requires ownership verification and correct mail routing.

The new mailbox service allocates actual records and stops the old placeholder from claiming an uncreated mailbox. It starts with bounded storage and sending, respects the existing global mail pause and delivery pipeline, and does not send mail during this audit. Production acceptance still requires DNS ownership/MX/SPF/DKIM/DMARC, successful external send and receive, queue processing, abuse handling and capacity checks. Do not promise Gmail-scale free storage or Gmail-equivalent deliverability.

## Launch sequence

**Before accepting money:** finish and verify the central YouTube upload/playback workflow; finish free-instance allocation and verified migration; connect creator subscriptions/live gifts/tips and their payout ledger; complete agency onboarding for purchasers; set real package costs/capacity; verify signed payment events through provisioned instance delivery; test cancellation/payment failure; test branded email externally. Keep sales paused until that acceptance is complete.

**Before inviting the first group:** publish at least one useful original video, three clips and a welcome post; create two or three focused communities with an owner and a first conversation; make the Free vs Personal offer obvious; test one invited ordinary user from signup to first post and message.

**First acquisition batch:** invite 10–20 relevant people personally through channels you already use, with a concrete reason to join (a live session, original program or specific community). Ask five potential Personal/Business users to try the complete paid flow once ready. This audit did not send invitations, publish marketing or spend money.

Suggested copy: “Your people. Your stories. Your own space. Join Lightek free—share, watch and build your community. Upgrade when you want a dedicated home for your content.” Explain the actual server/migration offer on the membership page rather than overloading that first sentence.

Track signup → email confirmed → instance ready → first post → first reply/message → return visit → membership checkout → verified payment → instance migration ready → renewal/cancellation. Count delivery, not checkout clicks, as a successful paid activation. No complete new funnel instrumentation is claimed by this branch.

## Validation and current limits

- New commercial/reference/paid-period checks: 12 tests, 55 assertions, passing.
- Mailbox suite including new branded-mail tests: 12 tests, 62 assertions, passing.
- Membership, remote-content and existing Nevaeh client JavaScript contracts: 18 tests, passing.
- Existing PWA HTTP suite: 39 tests, 214 assertions, one Studio publishing-idempotency error reproduced on the unchanged baseline.
- Existing administration suite: 65 tests, 414 assertions, three baseline errors (one Studio publishing-idempotency case and two missing branding-helper harness cases), reproduced on unchanged baseline. New dashboard regression found during implementation was corrected.
- Migration-version validation now passes after bringing the user’s exact migration corrections from `main` into this branch; new migration versions are distinct. No production migration was executed.
- Existing commerce regression suite: 40 tests, 127 assertions, passing after adding the paid-period hooks.
- Production payment, cloud allocation/migration, SMTP delivery and ordinary-user browser journeys were not performed. Private ecosystem/PostgreSQL integration, visual QA of the new screens and deployment remain pending.

## Central YouTube publishing and the creator earnings model

The required pipeline is **original video uploaded to the member instance → queued upload to Marlon’s Lightek YouTube channel → processing/rights/monetization checks → PWA plays the YouTube version**. The member’s instance retains the original and canonical ownership record. Never put the central channel’s OAuth credentials on a member instance. The upload worker needs a bounded authenticated media transfer, resumable upload, stable job identity, uncertain-upload reconciliation, provider processing-state checks and source update callbacks. A printed “upload successful” line is not an upload receipt. User redistribution consent and attribution belong in the publishing workflow.

This branch has embedded-player and earnings-report foundations; it does not implement that central uploader, connect the channel, verify YPP status or perform a production upload. Native source playback currently exists in baseline. Do not advertise the newly requested YouTube-first publication flow until it is implemented and accepted.

**User-facing presentation:** show “Your estimated earnings” and “Earnings per 1,000 views,” not the split as the main selling headline. Rates are calculated from the creator’s own reported views and attributable earnings. Example only: 10,000 views and $32 creator earnings produce $3.20 per 1,000 views. Another video can earn a different amount for the same views. Do not advertise a fixed guaranteed CPM/RPM or pay for artificial/incentivized views.

**Underlying terms:** the agreed paid-creator allocation is 80% of attributable channel proceeds after YouTube’s share, with 20% retained by Lightek. Free-tier view revenue remains Lightek’s; free and paid creators both retain all subscription/gift/tip principal. This branch records immutable verified paid periods and uses them for report eligibility, including after cancellation. To avoid guessing pre-upgrade vs post-upgrade views inside a daily report, the implemented rule starts sharing on the first complete Pacific reporting day within the paid period; mixed-period imports must use daily rows. Existing paid periods need verified receipt backfill before historical earnings can be imported accurately.

The official API’s video/day revenue is estimated. Finalized channel earnings and actual bank receipts can differ because of adjustments and withholding. Reconciliation therefore needs a channel-wide report, a documented allocation of final adjustments to videos, a source statement and a funds-received receipt before balances become available. If per-video final amounts are unavailable, use a disclosed proportional allocation based on that period’s official per-video revenue estimates, including the whole channel in the denominator. Do not pretend that an estimated video report is a finalized deposit.

### Creator subscriptions, lives and payouts

A platform infrastructure subscription is not a social creator subscription. The latter needs its own supporter → creator relationship, price, recurring payment, entitlement, renewal/cancellation and signed-event receipts. Live gifts/tips need creator identity, active session context, a fee quote, verified checkout and a durable earning before the audience sees a paid gift. A click or pending payment must not trigger a gift as paid.

For both free and paid creators: a $5 tip credits $5 principal to the creator; the supporter pays any clearly disclosed fee on top. The same principal rule applies to creator subscriptions and gifts. Processing/transfer charges must be funded explicitly, not silently taken from that principal. Refunds/disputes reverse the related earning through linked receipts and must not be silently funded from unrelated creators.

Required payout states: **estimated → reconciled → funded → available → transfer pending → transferred → bank paid**, with explicit failed/uncertain/held states. An internal transfer to a connected payout account is not proof that money reached the creator’s bank. Reuse Dymond Bank’s existing account verification and transfer rails, but implement a creator-specific earning/allocation/settlement ledger. YouTube deposits into the Lightek bank account do not automatically fund the processor balance used for connected-account transfers; the payout rail must actually be funded before release. This branch does not implement finalized revenue settlement or execute creator payouts.

Monthly reconciliation and a clearly disclosed minimum payout threshold can control transfer costs; amounts under the threshold roll over rather than disappear. Creator cash earnings already earned must survive subscription cancellation. Do not promise instant cashout from estimates.

## Official references

- YouTube developer policies: https://developers.google.com/youtube/terms/developer-policies
- YouTube monetization modules and eligible embedded playback: https://support.google.com/youtube/answer/94522?hl=en
- X Premium pricing: https://help.x.com/en/using-x/x-premium
- Discord Nitro reference: https://discord.com/blog/beginners-guide-to-nitro

- YouTube channel revenue reports: https://developers.google.com/youtube/analytics/channel_reports
- YouTube/AdSense finalization and payments: https://support.google.com/youtube/answer/14728151

## Teaching Nevaeh this work

The PWA revenue administration screen now has a targeted knowledge/training panel. It uses the existing installed-manual builder, dataset review, internal native model and sequential learning-plan acceptance. The source pack includes this audit and `docs/nevaeh/tutorials/pwa_business_model.md`; each batch retains source checksums. Preparing the pack synchronizes KB references when the installed KB engine is available. No unsupported execution phrases are activated. A changed source requires a fresh build. Actual training must run on the deployed application; this source change is not a claim that production weights have been trained or that unfinished launch features are executable.

Targeted Nevaeh learning validation: 6 tests / 29 assertions passed. Existing installed-manual learning regression: 12 tests / 282 assertions passed. These validate the source-build, provenance, approval and plan integration; production PWA checkpoint training has not run.
