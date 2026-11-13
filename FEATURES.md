# Lightek feature catalog

**Current source inventory: November 13, 2026, including merged PR #230.** Lightek connects business operations, creative production, communications, infrastructure and automation through the same Dashboard, accounts and service boundaries.

This is the current product inventory for the Rails host. Module guides describe supported formats, provider setup, limits and acceptance commands. An implemented connector still needs its real account, credentials, worker/runtime and live verification; a central deployment does not establish readiness on every independent client server. Historical module documents may describe an earlier delivery stage; use the newest linked workflow for current behavior.

## Find your workspace

| Goal | Start here | Guide |
| --- | --- | --- |
| Finish first super-admin sign-in | Sign-in security | [MFA setup and recovery](docs/security/sign-in-and-mfa.md) |
| Operate Nevaeh or delegate work | Nevaeh operating workspace; Control Center | [Operating workspace](docs/nevaeh_operating_system.md) |
| Build a website or publish an article | Design & Content | [Site themes and journal](docs/cms/site-themes-and-journal.md) |
| Sell and fulfill | Business; Commerce; Marketplace | [Platform operations](docs/commerce/platform-operations.md) |
| Manage the organization or payroll | People & Access | [People and payroll](docs/people/organization-benefits-payroll.md) |
| Keep books and reconcile statements | Finance → Books & accounting | [Enterprise operations](docs/enterprise-directory-and-accounting.md) |
| Read and send business email | Communications → Mail | [Mail operations](docs/mail/operations.md) |
| Book services or host a production room | Reservations & Experiences; Rooms & guests | [Reservations](docs/reservations_and_payouts.md) · [Rooms](docs/studio/session-rooms-and-audience.md) |
| Create media or go live | Studio & broadcasting | [Editors](docs/studio/open-source-editors.md) · [Live production](docs/studio/session-rooms-and-audience.md) |
| Manage servers, domains or client releases | Servers & applications; Network & Domains; Customer Updates | [Hosting](docs/server-application-management.md) · [Fleet updates](docs/customer_fleet_updates.md) |
| Manage a business from WordPress/Shopify | Lightek Connect | [Connect](docs/integrations/lightek-connect.md) |
| Read the installed manuals | Software Library; Nevaeh → Guide | [Library and contextual help](docs/nevaeh/digital_factory.md#software-library-and-contextual-help) |

Labels and visible destinations follow the installed navigation, account permissions and feature entitlements.

## 1. Shared Dashboard and business accounts

| Capability | Implemented behavior |
| --- | --- |
| Business overview | Operational sales/order/payment/inventory and workspace entry points use the existing business records. |
| Agency and client hierarchy | Nested managed accounts, client creation, inherited branding and upstream commercial terms. |
| Website context | Selected-site navigation connects Business, CMS, commerce, campaigns, Studio and PWA administration. |
| Account-specific branding | Client branding and sign-in presentation use the existing account-branding system. |
| Dashboard appearance | Fifteen palette controls, theme-preserving admin copies, compact forms, responsive navigation and redesigned Network & Domains sections. |
| Personal navigation | Saved per-account labels, groups, ordering, hidden entries and local shortcuts; shortcuts do not grant access. |
| Shared execution evidence | Tickets, work items, operation history, receipts and artifacts expose submitted, running, blocked, failed and accepted outcomes. |

Guides: [Dashboard appearance](docs/dashboard/appearance.md), [platform product contract](docs/platform/product-contract.md), [integrated business operations](docs/commerce/platform-operations.md).

## 2. Nevaeh operating workspace, agents and automation

| Capability | Implemented behavior |
| --- | --- |
| Conversational operating workspace | Authenticated commands, selected ordinary-language intents, voice input/replies where the browser supports them, action cards and receipts. |
| Typed capability dispatch | Existing native PWA/Studio/community/social/Susu and published intelligence operations run through saved actions, Gatekeeper and DymondDispatch. |
| Governed CRUD | Explicit resource contracts for workers, writing profiles, models, constructions, datasets, tickets, personas and application adapters. |
| Rails-style data console | `/models`, `/schema` and bounded `/rails` model expressions; authorized literal queries and supported mutations, without arbitrary Ruby or SQL evaluation. |
| Agent workforce | Persistent Nevaeh, Sage, Muse, Warden and custom agent identities; instructions, enable/pause state, autonomy settings and capability restrictions. |
| Delegated workers | Saved commands and structured workers with immutable input/run snapshots and downstream evidence. |
| Schedules | Recurring agent/structured workers using the existing minute sweep, deduplicated slots, permission rechecks and visible failure/block states. |
| Change-driven watchers | Ubuntu package/catalog/source changes and GitHub branch/new-repository observations; baseline-first detection and deduplicated events. |
| Watcher responses | Prepare/review/apply plans, selected-package updates or configured typed commands; pauses, leases and rule fingerprints protect changes. |
| Ubuntu application fabric | Governed package planning/setup, installed-document import, reviewed application contracts and bounded argument-array execution. Initial recipes cover FFmpeg, Pandoc and Blender version probing. |
| Memory and personas | Explicit memory-category consent and individual memory saves; personas change presentation/context, not authority. |
| Live capability Guide | `/help`, `/resources`, `/capabilities`, `/describe` and in-app tutorials show installed availability, inputs, permission and recovery guidance. |
| Software Library | Search/read installed repository manuals with containment checks and escaped content; contextual help drawers remain inside Dashboard. |

**Operating scope:** agents compose authorized supported actions. General model prose cannot execute tools; package documentation does not become an arbitrary application adapter. Host package/watch administration requires super-admin authority. New repositories produce onboarding evidence, not an automatic unreviewed production deploy.

Guides: [operating workspace](docs/nevaeh_operating_system.md), [agents](docs/nevaeh/tutorials/agents.md), [watchers](docs/nevaeh/tutorials/watchers.md), [Ubuntu applications](docs/nevaeh/tutorials/ubuntu.md), [commands](docs/nevaeh/tutorials/commands.md), [standalone CLI](docs/nevaeh_cli.md). The standalone CLI and the Rails-backed operating console have different execution contracts.

## 3. Nevaeh Digital Factory, writing and ticket execution

| Capability | Implemented behavior |
| --- | --- |
| Structured work orders | Ordered action sections, dependencies, named outputs, saved revision authorization and independent acceptance checks on the original Marlon ticket. |
| KB-driven execution | Procedure resolution, Gatekeeper checks, Dispatch work items, retry/revision paths and accepted output retained before verified closure. |
| Supported composition actions | Website page/section creation, Studio project creation, reviewed engineering generation and writing-draft generation. |
| Construction factory | Typed definitions compile constrained normalization, selection, renaming, defaults, composition and required-field operations into service/worker/verifier/test artifacts. |
| Verified activation | Independent sample expectations, source fingerprints and explicit release activation connect constructions to the existing registry/KB. |
| Writing services | Scripts, captions, posts and descriptions using rules, symbolic inference or an active native neural model. |
| Editorial direction | Supported tone, word-limit, opening and closing directives report applied and unsupported instructions. |
| Documentation learning | Public HTTPS reference import, source review, KB recording and reviewed dataset preparation. |
| Native neural training | Small Ruby language-model training, held-out metrics, immutable checkpoints, explicit activation/rollback and account-owned conversation history. |
| Studio script handoff | Generate/review writing drafts and apply the chosen result to the production's scene script. |

**Operating scope:** the native model is a small trained network, not a claim of general-purpose LLM parity. Construction uses authored primitives and sample tests. Unsupported tickets need a reviewed executor/verifier; generated code is not automatically merged or deployed.

Guides: [Control Center](docs/nevaeh/control_center.md), [Digital Factory](docs/nevaeh/digital_factory.md), [structured tickets](docs/nevaeh/structured_ticket_execution.md), [historical backlog execution](docs/nevaeh/historical_backlog_execution.md).

## 4. Websites, design, publishing and the PWA

| Capability | Implemented behavior |
| --- | --- |
| Pages & Sections | Existing site-owned page/section authoring, publication and registered section components. |
| Design Studio and starter library | Editable design/template starting points, theme controls and website starter installation. |
| HTML design imports | Queued conversion of supported HTML/CSS into owned editable designs/sections; original source retained. |
| Complete site-theme bundles | Assemble installed designs or multiple HTML pages, review before activation, shared header/footer, palette/fonts and real navigation. |
| Native store/journal sections | Store/cart/checkout and article areas render actual application records rather than demo catalog content. |
| Articles | Visual editing, draft/published/archive states, categories, excerpts, site-specific slugs and optimistic edit protection. |
| Public journal | Host-scoped article listing/search/category pagination, article URLs and RSS. |
| Shared article identity | Website articles share their canonical body/author with the existing PWA/community Post. |
| Per-site PWA | Application brand, install metadata, icon, accent/background, page settings and supported navigation/section controls. |
| Community and member administration | Public/private and configured audiences, memberships/roles, suspension, moderation and content/attachment management. |
| PWA operational controls | Site-scoped Studio/asset/operation review, live stopping, discussion close/reopen and administration audit. |
| Domain binding | Provisioned website/PWA initialization and deployment binding verification; independent instances keep their own databases. |

**Operating scope:** HTML imports do not execute uploaded scripts or install arbitrary WordPress plugins. Custom widgets/forms need application wiring. Dashboard colors and PWA colors are separate settings; the PWA does not yet have the full Dashboard palette editor.

Guides: [site themes and journal](docs/cms/site-themes-and-journal.md), [Design Studio](docs/lightek_design_studio.md), [HTML imports](docs/html_design_imports.md), [starter library](docs/website_template_library.md), [PWA administration](docs/lightek_pwa_administration.md).

## 5. Marketplace, commerce, subscriptions and shipping

| Capability | Implemented behavior |
| --- | --- |
| Marketplace product editor | Groups, one-time/free/monthly/yearly options, billing versions and reviewed delivery connections. |
| Store catalogs | Site-scoped products, variants, prices, inventory/stock rules and native storefront/cart integration. |
| Orders and payment lifecycle | Existing Bank/Stripe checkout, verified webhook handling, initial and recurring payments, failed/past-due/canceled states and order snapshots. |
| Fulfillment | Product/service delivery, application access, hosting handoffs and operational order status. |
| Subscriptions | Frozen purchased terms, renewals and cancellation through the existing billing contracts. |
| Refunds and payouts | Merchant workflows, processor onboarding, payout preferences and existing reconciliation gates. |
| Agency revenue terms | Nested upstream commercial terms, frozen allocations and reversals associated with sales. |
| Client-instance commerce | Authenticated peer-scoped checkout and synchronization of order, fulfillment, refund, subscription and payout updates. |
| Hosting retail | Approved infrastructure packages, provider cost ceilings/margins and distinct payer/application owner. |
| FedEx shipping | Merchant origin/parcel setup, platform carrier credentials in Vault, retail rates, paid-order label purchase, tracking and cancellation. |

**Setup:** configure the existing processor/webhooks, merchant payout eligibility, carrier account and retail/provider policies. Shipping currently targets domestic U.S. parcels and PDF labels; international customs, freight and pickups require more coverage. Carrier cancellation and payment refunds are distinct operations. Confirm the chosen website-delivery path in the hosting guide; historical Marketplace record creation alone is not proof of DNS/TLS installation.

Guides: [platform operations](docs/commerce/platform-operations.md), [Marketplace](docs/lightek_marketplace.md), [Bank lifecycle integration](docs/dymond_bank_lifecycle_v8_6d.md), [servers & applications](docs/server-application-management.md).

## 6. Books, statements, reconciliation and workbooks

| Capability | Implemented behavior |
| --- | --- |
| Employer-scoped books | USD bookkeeping accounts, reviewed opening balances and independently assigned accounting roles. |
| Statement imports | CSV/TSV/TXT mapping and bounded OFX/QFX parsing, review previews, transactional commit and duplicate/conflict handling. |
| Categorization | Categories, Schedule C mappings, literal keyword rules and audited bulk updates. |
| Reconciliation | Cleared transactions, outstanding checks/deposits, server-recomputed proofs, consecutive periods and reviewer finalization. |
| Period controls | Closed-period protection and controlled reopening of the most recent finalized period. |
| Reporting | Cash-basis monthly/annual profit and loss and Schedule C category workpapers. |
| Native workbooks | XLSX/delimited import, preserved worksheets/formulas, editable inputs and recalculation for a bounded native formula subset. |
| Spreadsheet conversion | Reviewed conversion into statement previews, categories and keyword rules. |
| Federal estimates | Versioned reviewed-input 2026 sole-proprietor estimates and safe-harbor worksheets. |
| Scheduled reporting | Permission-checked daily/weekly reporting and encrypted saved outputs. |
| Confidential records | Existing Vault encryption binds financial source data/workbook contents to their records; safe CSV exports and audit evidence. |

**Accounting scope:** statement imports do not credit spendable Bank funds or move money. This is cash-basis bookkeeping, not a completed double-entry/accrual ledger, full Excel replacement, universal tax calculator or IRS filing service. See [ERP completion workstreams](docs/platform/erp-completion.md) for receivables/payables, purchasing, inventory valuation and general-ledger acceptance still to close.

Guide: [enterprise bookkeeping, workbooks and estimates](docs/enterprise-directory-and-accounting.md).

## 7. People, benefits and payroll

| Capability | Implemented behavior |
| --- | --- |
| Default organization | Twenty-six seeded enterprise departments/subdepartments, including Shipping, Receiving and Legal & Compliance; custom/archived departments preserved. |
| Reporting structure | Managers, team leads, individual contributors and same-employer reporting chains with cycle validation. |
| Employment memberships | Employee/freelancer/agency membership, dates and independent employer access. |
| Separate authority | HR/people administration, IT directory administration, payroll preparation/approval, accounting and compliance roles. |
| Benefits | Published plans, employee elections and per-statement employee/employer contribution snapshots. |
| Reviewed payroll | Gross, reviewed taxes, deductions, benefits, net pay, employer costs and exported registers. |
| Independent approval | A different authorized reviewer approves; approved statement amounts and identities become immutable. |
| Employer-funded payouts | Vault-backed Stripe Global Payouts/Treasury sender and worker-hosted bank-detail onboarding. |
| Controlled release | Manual fee review/confirmation, stable idempotency, row locks and visible uncertain/returned/failed status. |
| Scheduled preparation | Prepare quotes for already-approved payroll; releasing funds remains an explicit action. |
| Employee self-service | Own approved statements and benefit elections; former workers retain their own historical statements while delegated authority ends. |

**Setup:** the employer must have an eligible funded processor financial account. Reviewed tax inputs are not automatic payroll tax calculation, remittance, W-2/1099 filing or carrier enrollment. Merchant-sale proceeds are not silently used as the payroll sender.

Guides: [People and payroll](docs/people/organization-benefits-payroll.md), [enterprise role separation](docs/enterprise-directory-and-accounting.md).

## 8. Identity, directory access and legal-source monitoring

| Capability | Implemented behavior |
| --- | --- |
| First-use accounts | Expiring first-password invitations, scoped resend, and an installed-application password handoff before MFA enrollment. |
| Authenticator MFA | Phone-scannable QR setup, manual-key fallback, time-based six-digit codes, protected enrollment, replay rejection, recovery codes and enrollment-only sessions. |
| Company policy | Required MFA and client acceptance of verified Connect MFA, while privileged/sensitive checks remain enforced. |
| Organization SSO | OIDC code/PKCE flow, explicit immutable-subject linking, local MFA and current membership checks. |
| Verified Connect handoff | Bind an agency's direct MFA session to the connection/client site, revalidate per request, preserve scope and enforce revocation/expiry. |
| IT directory administration | Explicit owner-appointed IT roles; directory principals and security-bearing department assignments remain outside ordinary HR authority. |
| Resource permissions | Explicit person/department grants for existing servers/applications with current membership/ownership checks. |
| Domain joining | Gatekeeper-managed remote Ubuntu joining to an existing AD/Samba AD realm and deny-first login allowlists. |
| Legislative monitoring | Open States legislative searches for selected jurisdictions and queries. |
| New York law search | Official Open Legislation adapter with source-linked results. |
| Evidence/review | Scheduled source snapshots, timestamps, stale/failed states and separately assigned compliance access. |

**Setup:** real IdP/domain/provider accounts, Vault credentials and reachability are required. Lightek does not create an AD controller or certify legal compliance. Legislative bills and search results are evidence for review, not a complete set of legal obligations. Authenticator changes, SSO linking and directory/access-policy mutations retain direct sign-in requirements.

Guides: [first sign-in](docs/security/sign-in-and-mfa.md), [enterprise identity and legal monitoring](docs/enterprise-directory-and-accounting.md), [Connect MFA](docs/integrations/lightek-connect.md#verified-agency-mfa-handoff).

## 9. Lightek Mail and business communications

| Capability | Implemented behavior |
| --- | --- |
| Domain/mailbox administration | Verified customer domains, enabled-by-default new mailboxes, display-name editing and confirmed retirement/deletion. |
| Webmail workspace | Folder rail, message list, reader, search operators, pagination, stars/read state, bulk actions and guarded undo. |
| Conversation handling | Threaded history, Reply/Reply all with original context, forwarding and draft persistence. |
| Composition and attachments | Rich text plus plain-text fallback, docked composer, attachments and bounded sandbox previews. |
| Distribution addresses | Same-customer mailbox groups, deduplicated copies and recipient snapshots across retries. |
| Junk controls | Fresh Rspamd-based classification, Junk folder, spam/not-spam actions and standard/strict sender/domain controls. |
| Templates and automatic replies | Mail settings reuse the existing template and auto-reply services with sending policy checks. |
| Sending and ingress APIs | Mailbox-scoped HTTPS submission, idempotency, authenticated inbound envelope routing and durable inbox records. |
| Transactional mail | Existing Lightek SMTP transport for application mail and an operator delivery-check/receipt workflow before legacy Gmail credential retirement. |
| Receiving integration | Existing Postfix recipient-sync/pipe helpers, automatic verified-address publication and safe route revocation. |

**Setup:** verify DNS, MX, SPF/DKIM/DMARC, PTR, SMTP egress, receiving routes and scanner health on the actual host. Browser mail availability does not prove inbox placement. Incoming scanner outages hold affected mail in Junk. Native IMAP/POP mailbox synchronization and complete calendar/contact/groupware coverage are separate work.

Guides: [Mail operations](docs/mail/operations.md), [sending controls](docs/mail/sending-controls.md).

## 10. Reservations, guests and conferencing

| Capability | Implemented behavior |
| --- | --- |
| Bookable experiences | Appointments, meetings, voice/video/live services, equipment/venues and configured server packages. |
| Availability | Time zones, opening hours, notice, buffers, blocked periods and overlap/capacity protection. |
| Booking lifecycle | Customer reservations, payment-confirmed access, cancellation/rescheduling, calendar files, receipts and reminders. |
| Front desk | Day/calendar agendas, manual booking, check-in/completion and visible recovery states. |
| Server resort packages | Approved retail compute packages, reservation-bound allocation, renewals, change quotes and guarded resize application. |
| Private production rooms | Create/schedule rooms and invite existing accounts without a synthetic paid reservation or order. |
| Host controls | Waiting/admission, lock, mute, removal, end-room and host-broadcast notice. |
| Self-hosted media | Per-site managed LiveKit activation through the registered installation and existing Vault/Gatekeeper transport. |
| Studio handoff | Independent participant media enters the existing compositor as one program picture/audio output. |

**Setup:** room service activation is explicit. The managed installer requires suitable capacity, dedicated HTTPS routing and media firewall reachability; the documented minimum is 2 GB RAM. Validate real camera/microphone access and cross-network connectivity. Server pause is not deletion and does not stop provider infrastructure charges.

Guides: [reservations and payouts](docs/reservations_and_payouts.md), [rooms, guests and media activation](docs/studio/session-rooms-and-audience.md).

## 11. Studio: photo, video, music and production

| Capability | Implemented behavior |
| --- | --- |
| Photo Studio | Locally served miniPaint interface with layers, selection, painting, text, crop/resize and filters. |
| Video Studio | Locally served Movie Masher timeline, tracks, player, inspector, titles/shapes and supported effects. |
| Saved editable projects | Existing production/scene storage, source revisions, save-conflict protection and JSON backup/restore. |
| Basic exports | PNG/MP4 exports into the existing media library, downloadable results and isolated server-side video rendering. |
| Campaign connection | Create/reopen a campaign production with its brief and return link, retaining website context. |
| Native Blender library | Approved demo/source imports, prepared metadata, pinned editable `.blend` attachments and optional GLB browser proxies. |
| Native authoring | Outliner/Inspector, source-object transforms, visibility, duplication/removal, cameras, lights, material overrides and exposed Geometry Nodes parameters. |
| Advanced workstation/finishing | Existing Blender workspaces and a separate timeline/mix/export path with transforms, fades, speed, titles, picture adjustments, MP4/ProRes and WAV output contracts. |
| Cast & Performance | Native toon creation or compatible packed character registration, placements, recorded audio takes, saved facial/gesture cues and animated preview/shot export. |
| Show templates | Reusable scenes, cast, sets/cameras, production plans, scene objectives and independent episode/project copies. |
| Music composition | Step sequencer, piano roll, instruments/samples, multi-bar arrangement, gain/pan/mute/solo and sound shaping. |
| Music delivery | Saved scores, WAV mix/stems, MIDI export and a linked mix-to-edit handoff. |
| AI Studio integration | Loopback ComfyUI readiness, operator recipes, prompt/seed jobs, durable asset ingestion and result-to-edit. |
| Production delivery | Existing artifact/library reuse, publication records, release queues, channel/OTT configuration and destination adapters. |

**Editor contracts:** the new basic editor path and the advanced legacy/native production path coexist. Basic photo/video PNG/MP4 exports use existing instance resources without an added checkout. Advanced Blender/render/finishing operations retain their documented quote/payment workflows. The basic video editor currently supports up to 16 tracks/128 clips/ten minutes and a 1920-pixel maximum canvas dimension; the advanced finishing path has its own clip/output limits.

**Engine scope:** the browser preserves native Blender rigs/node graphs but does not implement every Blender/Maya authoring tool. Cast mouth automation follows audio volume, not automatic phoneme/viseme alignment. AI concept-image generation requires an installed local engine/checkpoint; automatic model/GPU provisioning, proven AI video/voice/3D recipes, face replacement and voice cloning are not delivered by that generic adapter. Full Resolve/Maya parity and automatic finished-episode generation remain separate acceptance goals.

Guides: [basic editors](docs/studio/open-source-editors.md), [Blender engine](docs/studio/native-blender-engine.md), [native authoring](docs/studio/blender-authoring.md), [production finishing](docs/studio/production-suite.md), [cast](docs/studio/cast-and-performance.md), [music](docs/studio/music-quickstart.md), [AI Studio](docs/studio/ai-studio.md), [production roadmap](docs/studio/roadmap.md).

## 12. Live production, audience and distribution

| Capability | Implemented behavior |
| --- | --- |
| Live production sources | Existing camera/capture and prepared scene/library sources plus subscribed room media. |
| Professional presentation | Panel/gallery, presenter/sidebar, interview/side-by-side and featured layouts with names/roles, brand colors, lower thirds and scrolling banner. |
| Program composition | Combined presentation canvas and audio mix, holding-screen behavior and prepared Blender/GLB-stage presentation surfaces. |
| Native and Restream output | Existing Live Studio output paths to Lightek community and configured Restream destinations. |
| Lightek audience desk | Authorized playback activity and existing community replies under the site's access rules. |
| Restream chat | Configured chat embed for supported platforms; distinct from the outgoing stream connection. |
| TikTok events | Explicit TikTok-Live-Connector reader for public live chat, arrivals/count updates, gifts and related normalized events. |
| Social Stream Ninja | Optional configured session/relay integration for aggregated audience events. |
| OTT/channel management | Existing content, publication, release and schedule settings for configured Lightek streaming/OTT clients. |

**Provider scope:** an RTMP stream does not prove the audience reader is connected. TikTok uses an unofficial upstream/signing-provider path; social adapters require current account/configuration verification. Named arrivals are not a complete current viewer roster, and overlapping adapter counts are not summed. A Roku/OTT endpoint or schedule is not evidence of a submitted/approved store application or successful playback on every device.

Guides: [rooms and audience](docs/studio/session-rooms-and-audience.md), [broadcast control room](docs/studio/broadcast-control-room.md), [publisher contract](docs/studio/publisher-contract.md), [PWA administration](docs/lightek_pwa_administration.md).

## 13. Cloud, hosting, domains and application lifecycle

| Capability | Implemented behavior |
| --- | --- |
| New server + application | Background provider allocation and application install, initially Linode/Ubuntu with registered templates. |
| Existing server installation | Install an authorized independent application without allocating another server. |
| Shared websites | Add a website to an existing Rails runtime under existing quotas. |
| Runtime registration | Register code already installed, with an explicit deployment profile and ownership. |
| Application templates | Native Lightek Rails and digest-pinned container images, with configured database/Redis/worker services as applicable. |
| Integrated image builds | Selected repository branch/commit, private-gem packaging, GHCR publication and verified build callback/template registration. |
| Domains and DNS | Existing GoDaddy-backed domain/DNS workflows, zone records, verification and infrastructure context. |
| Vault-backed connections | Provider, deployment, registry and signing credentials checked out for explicit consumers/purposes. |
| Provisioning recovery | Durable launches/requests, receipt-based readiness and retry using the same allocated server where supported. |
| Server deletion | Explicit authorized provider deletion with in-flight installation checks and retained history. |
| Client updates | Exact-release deployment to selected installations, one account or matching fleet. |
| Rollout controls | Canaries, batching, scheduling, pause/cancel/retry, optional promotion and customer-specific assigned-release pins. |
| Multiple update adapters | Native Rails/Passenger, explicitly containerized applications, configured Nginx CDN and systemd services. |
| Release verification | Running revision and health checks, protected logs, backup hooks and installation receipts. |

**Deployment scope:** the standard Rails application remains native under Passenger; Docker dependencies do not imply a containerized Rails app. Images are built/published through the integration rather than requiring the customer to create a Docker Hub image. Existing DNS authority, provider permissions, private repository/package access and public TLS must be configured and verified. Fleet targets are explicit; central success alone is not client-fleet success.

Guides: [servers & applications](docs/server-application-management.md), [Customer Updates](docs/customer_fleet_updates.md), [deployment integration](docs/lightek_deployment_integration.md), [storage](docs/deployment-storage.md).

## 14. Lightek Connect, Vault and platform safeguards

| Capability | Implemented behavior |
| --- | --- |
| WordPress connection | Per-administrator pairing and connected agency workspace with existing Lightek backend access. |
| Shopify connection | App Bridge staff identity validation and Vault-backed application credential configuration/rotation. |
| Managed-site actions | Permission-filtered sites/deployments, website rename and secure full-Dashboard/client management handoffs. |
| Verified MFA continuity | Browser verification, original source-session reuse, tenant-bound grants and per-request issuer validation over existing federation transport. |
| Disposable WordPress testing | Operator-managed isolated WordPress/database/HTTPS setup and owned-resource cleanup on an existing eligible server. |
| Scoped Vault | Encrypted secret records, consumer/purpose policies, audited checkout and verified original-key recovery. |
| Tenant protection | Site/account/employer scope in controllers/services/workers, with independent permissions for financial and infrastructure work. |
| Safe operating states | Explicit blocked/needs-review/uncertain results, idempotent request keys and source/output evidence where implemented. |

**Activation:** WordPress/Shopify installations, client-server handoffs and paid provisioning need live acceptance on their actual accounts. Marketplace submission, new external app providers, broad compliance certification and unrestricted autonomous repair are not established by these integration interfaces.

Guides: [Lightek Connect](docs/integrations/lightek-connect.md), [Vault recovery](docs/server-application-management.md#vault-key-recovery), [sign-in and recovery](docs/security/sign-in-and-mfa.md).

## Release evidence and keeping this catalog current

The final PR #230 enterprise/Connect harness passed **80 tests / 743 assertions** on Rails 8.0.5/PostgreSQL 16, with separate Connect, People/payroll and deployment-preflight checks passing. [Recorded enterprise run](https://github.com/Mrlightek/lightekmcg-site/actions/runs/43491056481). Its cross-server transport is replaced in-process; real deployed provider/host acceptance is a separate result. Other modules have their own checks and recorded limitations in the linked guides. This inventory does not declare every repository workflow green.

When a capability changes, update its owning guide and this catalog, retain the exact verification boundary, and keep the installed registry/KB procedure aligned. Put future targets in the [product contract](docs/platform/product-contract.md), [ERP workstreams](docs/platform/erp-completion.md) or [Studio roadmap](docs/studio/roadmap.md), so operators can distinguish current workflows from work still to finish.
