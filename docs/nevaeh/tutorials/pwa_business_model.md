# Lightek PWA business model and launch knowledge

## Source and completion status

This is the reviewed product policy from the November 17 PWA audit and implementation work. Read the installed source and current runtime receipts before answering. Source implementation, passing local tests, production deployment, native-model training and successful customer delivery are different states. The detailed evidence and unfinished work are in `docs/pwa_launch_audit_20261117.md`; the current operational acceptance steps are in `docs/pwa_launch_candidate.md`. Never describe this draft as a completed production launch.

## Free member hosting

The target is a lightweight, separately scoped member application on shared Lightek hosting. Free members can participate in the social network. Shared hosting must enforce per-member and total capacity limits. Automatic member-instance allocation has not been connected in this implementation; do not tell a new member that signup alone has provisioned a server.

## Personal membership and pricing

Personal moves the same member application to its own separately allocated server. The existing configured hosting package supplies its actual monthly price. A $9.99 entry target is a proposal, not a guaranteed available offer. Server costs, processing, backup, transfer, mail and margin must fit the price. Never claim unlimited storage or rendering.

## Business and Agency membership

Business is the Agency tier: business identity, white label branding, client relationships, feature controls and resale of client server packages. Each client package must cover its own costs and is billed separately. Verified active Business purchases now activate the member’s own white-label role and agency profile idempotently, preserving existing upstream relationships and branding. Staff roles cannot be converted by this path. Checkout creation/return grants no role. The full paid offer remains blocked pending allocation, migration and cash settlement. Payment never grants platform-super-administrator powers.

## Instance upgrades and data preservation

Keep one stable member identity and address when moving from shared to dedicated hosting. Copy and verify the member's own data and files, pause writes for the final delta, switch routing, verify the destination and retain rollback. Automatic verified migration is unfinished. Existing central posts block the new self-service checkout rather than silently replacing a populated account with an empty server.

## Central references and source ownership

The central database is the discovery and social index. References retain owner, content ID, title/type and source URL. Body and media stay on the member instance. Known authenticated peers send versioned updates and deletion notices; central derives the source origin and author from the verified installation. Repeated or older revisions cannot resurrect a removed reference. Private and restricted content must not be syndicated publicly.

## Required central YouTube pipeline

The required route is original video uploaded to the member instance, then queued upload to Lightek's central YouTube channel, followed by processing checks, then YouTube playback in the PWA. Keep the channel's credentials on trusted central infrastructure. The central uploader is now implemented: rights/audience consent, exact channel verification, authenticated source grants, bounded checked original transfer, Vault-held resumable sessions, duplicate-safe recovery, processing checks and withdrawal. It needs actual channel authorization and production acceptance; local tests do not establish a real upload. Originals stay on the source. Expired uncertain sessions require reconciliation, not blind re-upload. See `docs/pwa_launch_candidate.md` for operations.

## View earnings for paid creators

Paid creators participate in view earnings from launch. The underlying policy allocates 80% of attributable channel proceeds after YouTube's share to the eligible paid creator and 20% to Lightek. These are channel proceeds, not advertiser gross spend. Free-period view revenue belongs to Lightek. An upgrade does not retroactively claim earlier free-period revenue.

## Earnings per one thousand views

Lead the member interface with reported views, estimated creator earnings and earnings per 1,000 views. Calculate the rate from that creator's own reported earnings and views. Example only: $32 of creator earnings from 10,000 views is $3.20 per 1,000 views. The rate varies; do not promise a fixed amount for every view. Explain the allocation transparently in the revenue terms.

## Historical paid eligibility

Verified checkout and paid renewal receipts create historical paid-period records. Canceling a subscription does not erase eligible earnings already earned. The implemented daily-report rule starts sharing with the first complete Pacific reporting day inside a paid period. Split mixed-period reports into daily rows; do not invent which views occurred before a partial-day upgrade. Existing histories need verified receipt backfill.

## Estimated earnings are not cash

A YouTube video/day report is an estimate. Finalized channel amounts can change. Reconcile official channel reports with final statements and received funds, including a documented allocation of adjustments. Imported estimates must not become a withdrawable balance or trigger a payout automatically.

## Creator subscriptions, gifts and live tips

Free and paid creators keep 100% of subscription, gift and tip principal. The supporter pays any disclosed processing/network charge on top. A $5 tip credits $5 principal to its creator. A supporter-to-creator subscription is distinct from a member's infrastructure subscription. Creator offers, disclosed-fee quotes, canonical signed checkout/invoice settlement, monthly support entitlements/cancellation, live gifts/tips, payment history and a creator-specific principal ledger are implemented. These are financial-support subscriptions; subscriber-only post access is not implemented. Live gifts require a matching currently live public session and a verified payment receipt; pending clicks never count. Production collection remains unverified.

## Payout execution and receipts

Use Dymond Bank's existing verification and payout infrastructure with a creator-specific ledger. Estimated, reconciled, funded, available, transfer-pending, transferred and bank-paid are separate states. A transfer to a connected payout account is not proof of bank settlement. YouTube receipts in the Lightek bank do not automatically fund a processor transfer balance. Creator support releases now check the real source charge and available balance transaction, block refunds/disputes, verify the payout account and transfer full principal with a durable destination and idempotency key. An uncertain transfer remains transfer_pending for reconciliation. Refund/dispute recovery targets its own transfer. Production release/bank delivery and the separate funded YouTube cash-settlement implementation remain unverified or missing. Never mark an uncertain transfer paid or deduct a hidden platform cut from creator principal.

## Lightek branded member mail

Members can receive real Lightek-domain mailboxes after confirming the signup email. The implementation starts at 250 MB storage, 20 recipients per day and bounded minute/hour limits. The feature is closed until enabled on a verified platform-owned mail domain. The account is mailbox-scoped; it does not give the member control of the platform domain. An assigned address without a real mailbox is not provisioned mail.

## Business custom-domain mail

Business accounts can choose email at their own verified domains. Ownership verification, routing and successful send/receive are required. A free branded mailbox alone does not grant custom-domain administration. Larger paid mailbox allowances are a product goal, not an implemented automatic quota upgrade.

## Launch UX and verified value

Keep a simple community home, clear creation/discovery paths, a focused membership page and secondary services under More. Use actual package prices and distinct payment/delivery states. Do not describe an offline shell as an offline posting queue. A visible button is not proof that its operation works.

## Unfinished execution coverage

Automatic free-instance allocation, verified migration and finalized/funded YouTube view-earnings settlement are not implemented. They block the complete launch and new paid instance sales through LaunchReadiness. Central YouTube publishing, creator subscriptions/live gifts/tips and support-principal release are implemented but still require production acceptance. No executable Nevaeh contracts for those unfinished operations are added by this guide. Answer from the guide, explain the gap, or use an existing authorized task; do not fabricate a completed operation.

## Learning and acceptance

PWA Administration → Memberships & YouTube revenue provides a targeted Nevaeh learning panel. Prepare source-linked batches, inspect the manuals and examples, then train reviewed material with an enabled internal model. The existing sequential learning plan checks source fingerprints, approvals, trainer metrics and checkpoint acceptance. Only a passing activated checkpoint is a completed native-model update. Check a real runtime receipt before claiming that Nevaeh has trained or mastered this material.
