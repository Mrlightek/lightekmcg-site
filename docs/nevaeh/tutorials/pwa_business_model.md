# Lightek PWA business model and launch knowledge

## Source and completion status

This is the reviewed product policy from the November 17 PWA audit and implementation work. Read the installed source and current runtime receipts before answering. Source implementation, passing local tests, production deployment, native-model training and successful customer delivery are different states. The detailed evidence and unfinished work are in `docs/pwa_launch_audit_20261117.md`; the current operational acceptance steps are in `docs/pwa_launch_candidate.md`. Never describe this draft as a completed production launch.

## Free member hosting

Free members participate through the central social app, while their original posts/uploads live on separate shared member servers. Automatic native backend allocation is connected through a durable signup request, a capacity-bounded separate pool and recovery jobs. Signup creates a request, not an instantly ready server; show preparing/ready states and never fall back to the central server.

## Personal membership and pricing

Personal moves the same member application to its own separately allocated server. The existing configured hosting package supplies its actual monthly price. A $9.99 entry target is a proposal, not a guaranteed available offer. Server costs, processing, backup, transfer, mail and margin must fit the price. Never claim unlimited storage or rendering.

## Business and Agency membership

Business is the Agency tier: business identity, white label branding, client relationships, feature controls and resale of client server packages. Each client package must cover its own costs and is billed separately. Verified active Business purchases now activate the member’s own white-label role and agency profile idempotently, preserving existing upstream relationships and branding. Staff roles cannot be converted by this path. Checkout creation/return grants no role. The full paid offer remains closed until separate-host allocation and all commercial configuration checks pass, followed by explicit owner enablement and deployed acceptance. Payment never grants platform-super-administrator powers.

## Instance upgrades and data preservation

Keep one stable member identity and address when moving from shared to dedicated hosting. Copy and verify the member's own data and files, pause writes for the final delta, switch routing, verify the destination and retain rollback. Shared native backends now migrate through a durable root-SSH operation: freeze writes, copy the complete application database, original media, encryption/signing keys and queue data, verify schema/counts/media hashes, revoke source sessions in the destination, activate, update stable central post references and redirect the retained source. Source and destination code revisions must match. Rollback restores the unused destination first and then thaws the source; once destination activation starts, a reverse transfer is required to preserve new writes. Historical central originals stay readable in the existing database and do not block upgrades. New originals publish on member backends; a shared-to-paid transfer moves the data stored on that shared backend, without claiming to have moved central history. Existing paid instances do not receive a redundant free allocation.

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

Use Dymond Bank's existing verification and payout infrastructure with a creator-specific ledger. Estimated, reconciled, funded, available, transfer-pending, transferred and bank-paid are separate states. A transfer to a connected payout account is not proof of bank settlement. YouTube receipts in the Lightek bank do not automatically fund a processor transfer balance. Creator support releases now check the real source charge and available balance transaction, block refunds/disputes, verify the payout account and transfer full principal with a durable destination and idempotency key. An uncertain transfer remains transfer_pending for reconciliation. Refund/dispute recovery targets its own transfer. Finalized view settlement now retains a whole-channel daily report and finalized monthly channel receipt, scales eligible video revenue using the complete channel denominator, and creates immutable creator allocations. A separately funded platform top-up must be API-confirmed succeeded/available and cover the liability. Reserved support principal cannot be spent on view earnings. Platform automatic bank payouts must be manual while funds are reserved. View transfers retain their destination/key, recover lost responses from provider history, and block blind retries beyond the idempotency window. Production release and bank delivery remain unverified. Never mark an uncertain transfer paid or deduct a hidden platform cut from creator principal.

## Lightek branded member mail

Members can receive real Lightek-domain mailboxes after confirming the signup email. The implementation starts at 250 MB storage, 20 recipients per day and bounded minute/hour limits. The feature is closed until enabled on a verified platform-owned mail domain. The account is mailbox-scoped; it does not give the member control of the platform domain. An assigned address without a real mailbox is not provisioned mail.

## Separate free-member hosting

Free member content must never fall back to the central Lightek server. The owner provisions a separate shared pool through PWA revenue administration, selecting a native package, member capacity and approved monthly budget. The provider price and RAM/disk admission checks must pass. Each member gets a separate native application, database, queue and storage directory on that host; this is application/database separation, not a separate machine per free user or a container security boundary. The current native profile shares its system application user. Start with a small pilot and verify resource use before increasing capacity.

Signup persists an allocation request before enqueueing. A full/unavailable pool keeps the free account and queues backend setup; it does not write new original posts or uploads centrally. Standard member attachment allowance is 512 MB; the smallest starter profile uses 256 MB. Native dependency/worker caps and one web process per application reduce contention; admission estimates are not proof of load-test capacity. The central member uses Membership → My publishing space → Create a post; the short-lived one-use ticket preserves the normal MFA flow. The source navigation returns to the central community, membership and earnings pages.

## Business custom-domain mail

Business accounts can choose email at their own verified domains. Ownership verification, routing and successful send/receive are required. A free branded mailbox alone does not grant custom-domain administration. Larger paid mailbox allowances are a product goal, not an implemented automatic quota upgrade.

## Launch UX and verified value

Keep a simple community home, clear creation/discovery paths, a focused membership page and secondary services under More. Use actual package prices and distinct payment/delivery states. Do not describe an offline shell as an offline posting queue. A visible button is not proof that its operation works.

## Unfinished execution coverage

Allocation, migration, central YouTube publishing, creator support and finalized/funded view settlement are implemented services with local evidence. Native and production acceptance remain outstanding. Their dedicated Nevaeh Dispatch executors are not registered by this guide or by preparing a source build. Answer from current sources, identify missing execution contracts, or use an existing authorized task; do not fabricate an executed operation, trained checkpoint or production success.

## Learning and acceptance

PWA Administration → Memberships & YouTube revenue provides a targeted Nevaeh learning panel. Prepare source-linked batches, inspect the manuals and examples, then train reviewed material with an enabled internal model. The existing sequential learning plan checks source fingerprints, approvals, trainer metrics and checkpoint acceptance. Only a passing activated checkpoint is a completed native-model update. Check a real runtime receipt before claiming that Nevaeh has trained or mastered this material.


## Smallest free server and owner-controlled placement

The owner requested the actual smallest server, not a larger comfort tier. Revenue administration now offers the smallest live priced 1 GB-or-larger plan, with a constrained starter profile: one member slot, 256 MB media allowance, 2 GB swap and serialized web application processes. This is a pilot; deployment, sign-in, publishing and resource behavior on the real 1 GB host still require acceptance. Never call swap equivalent to RAM or claim the server has been purchased from local tests.

The super administrator can add more free-member servers, change the default and select round robin across ready pools. These are backend-placement decisions for new members; changing the default does not migrate existing members or send each HTTP request to a different database. Full, paused or invalid pools never receive new reservations and never fall back to the central host. Member-slot capacity notifications appear in the operator's Dashboard every threshold transition, with a five-minute sweep and no automatic upgrade/spending. A one-slot starter alerts at its first reservation; larger pools alert with one remaining slot or 80% reserved, then at full. Do not describe these as measured memory/disk alerts or confirmed external email delivery.

Imported sites remain under their existing tenant. Global super-administrator administration plus explicit platform setup records the responsible operator in a protected database binding; no ordinary user can change that binding. New UI/service methods are not automatically Nevaeh Dispatch executors. Prepare a fresh reviewed source build before training from this updated guide.
