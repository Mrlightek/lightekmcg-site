# Lightek Media & Communications Group

**Lightek is a business operating system connecting websites, commerce, finance, people, communications, media production, infrastructure and automation in one Dashboard.** This repository is the Rails host application for that ecosystem and its client-facing experiences.

A business can build its website, sell products or book services, manage customer communications, produce media, run its own applications and delegate supported work to Nevaeh using the same accounts and operational records. Agencies can manage nested client businesses and independently provisioned client instances through the existing account, billing and Gatekeeper boundaries.

**Built IT-first:** business teams get usable products; IT gets explicit access boundaries, execution evidence and recovery paths in the same system. See the [operating contract](docs/platform/it-first-operations.md).

## Start here

| What you need | Where to go |
| --- | --- |
| Manage leads, deals, follow-ups and forecasts | [Sales & CRM](docs/sales/crm.md) · [Inquiry intake & tasks](docs/sales/intake-and-follow-through.md) |
| Onboard/offboard employees or agencies | [Lifecycle operations](docs/people/onboarding-offboarding.md) |
| Turn an approved quote into an order and delivery | [Quotes to delivery](docs/sales/quotes-to-delivery.md) |
| The full current feature list | [Lightek feature catalog](FEATURES.md) |
| Production is asking you to set up an authenticator | [First sign-in, MFA and recovery](docs/security/sign-in-and-mfa.md) |
| Set up and manage a payout account | [Payout accounts, verification and connection repair](docs/payments/payout-accounts.md) |
| Use consistent dashboard forms and order actions | [Dashboard form patterns and order management](docs/dashboard/forms.md) |
| Learn Nevaeh, agents, workers, watchers and commands | [Operating workspace and Guide](docs/nevaeh_operating_system.md) · [Tutorials](docs/nevaeh/tutorials/commands.md) |
| Train on installed manuals and teach conversational tasks | [Manuals & Language](docs/nevaeh/tutorials/manual_learning.md) |
| Import Quran/hadith sources and extend native training | [Islamic learning and source attribution](docs/nevaeh/tutorials/islamic_learning.md) |
| Schedule Quran study and training at Salah times | [Salah & Study on the server clock](docs/nevaeh/tutorials/salah_study.md) |
| Edit a photo or video and export it | [Photo and Video Studio](docs/studio/open-source-editors.md) |
| Render procedural scenes with a bounded CPU budget | [CPU economy rendering & recovery](docs/studio/cpu-economy.md) |
| Route CPU renders to dedicated Lightek workers | [Shared CPU worker deployment & recovery](docs/studio/shared-cpu-workers.md) |
| Render supported procedural movies from a client installation | [Remote CPU bridge](docs/studio/remote-cpu-rendering.md) |
| Control Blender modifiers and stack order | [Modifier stack](docs/studio/blender-modifier-stack.md) |
| Direct and render a shot sequence | [Shots & Storyboard](docs/studio/shots-and-storyboard.md) |
| Position a graphic or logo in the live program | [Live graphic placement](docs/studio/live-overlay-placement.md) |
| Feature a viewer comment on the live program | [Audience comment graphics](docs/studio/live-audience-graphics.md) |
| Direct guests in the live program | [Guest visibility, order and audio](docs/studio/live-guest-program.md) |
| Reuse production assets and branding for a live show | [Saved live production setups](docs/studio/live-production-setups.md) |
| Track Studio implementation and final verification | [Feature sprints](docs/studio/feature-sprints.md) |
| Play instruments into editable notes | [Performance recording](docs/studio/music-performance.md) |
| Score a production against picture | [Picture scoring & cues](docs/studio/music-picture-scoring.md) |
| Record a full pass or punch selected song bars | [Microphone overdub](docs/studio/music-overdub.md) |
| Record and arrange audio takes | [Recording & audio takes](docs/studio/music-recording.md) |
| Group instruments and process the mix | [Mixer buses & inserts](docs/studio/music-mixer.md) |
| Automate channels, groups, master and effect settings | [Music automation](docs/studio/music-automation.md) |
| Compose reusable music patterns | [Patterns & playlist](docs/studio/music-patterns.md) |
| Finish Blender materials and scene look | [Look & materials](docs/studio/look-and-materials.md) |
| Arrange character motion | [Body motion clips](docs/studio/body-motion-clips.md) |
| Animate dialogue on a character | [Character speech & lip sync](docs/studio/character-lip-sync.md) |
| Animate a library still into a video shot | [Genesis image-to-video](docs/studio/genesis-image-to-video.md) |
| Set up a self-hosted generation worker | [Genesis workers & model packages](docs/studio/genesis-workers.md) |
| Create a website or publish articles | [Design & Content](docs/cms/site-themes-and-journal.md) |
| Configure books, people, payroll or company security | [Enterprise operations](docs/enterprise-directory-and-accounting.md) · [People and payroll](docs/people/organization-benefits-payroll.md) |
| Operate a server or update client installations | [Servers & applications](docs/server-application-management.md) · [Customer Updates](docs/customer_fleet_updates.md) |

These guides are also discoverable in **Dashboard → Software Library** after the updated repository is deployed. **Nevaeh → Guide** describes installed commands and capability availability. Access to each workspace still follows the signed-in account's permissions and feature entitlements.

## What is in the platform now

*Platform baseline: November 13, 2026, PR #230; Studio inventory and workflow links refreshed November 15, 2026. This describes implemented host workflows; it is not a claim that every external provider or every deployed client instance has passed live acceptance.*

| Workspace | Current capabilities |
| --- | --- |
| Business, agencies and Marketplace | Business overview, managed account hierarchies, client branding, products, billing versions, subscription intervals and reviewed fulfillment connections |
| Campaign performance | Pinned reviewed versions, separate placement cohorts, immutable measured reviews and editable follow-up drafts through Nevaeh; [guide](docs/nevaeh/tutorials/growth.md#campaign-performance-and-follow-up-experiments) |
| Website growth audit | Native CMS evidence, guided metadata/CTA/alt previews, verified rechecks and guarded rollback; [operating guide](docs/sales/website-growth-audits.md) |
| Publishing calendar | Finished Studio export handoff, reviewed social schedules and provider outcome recovery; [operating guide](docs/sales/publishing-calendar.md) |
| Recipe-driven episode Director | Reuses long-form production templates and show bibles, creates independent scenes with editable camera coverage, queues local stock-voice dialogue/captions, directs bound Cast performances, quotes scene renders, assembles private episode masters, and delivers reviewed community/OTT or configured TikTok/Instagram publications; [operating guide](docs/nevaeh/tutorials/production_director.md) |
| Conversational campaign producer | Native TikTok draft recipe: timed script/storyboard, editable portrait timeline, graphics or owned images, music and captions, private MP4 preview and retry receipts; [operating guide](docs/nevaeh/tutorials/campaign_producer.md) |
| Campaign content & review | Three shared-writer copy variations, saved-revision approval, queued payload checks and focused Studio production; [operating guide](docs/sales/campaign-content-review.md) |
| Growth & attribution | Daily Nevaeh growth plans with evidence and editable campaign drafts, site-scoped business briefs, first-party campaign links and visit cohorts traced through inquiries, deals, confirmed payments, refunds and recorded delivery; [operating guide](docs/sales/growth-foundation.md) |
| Sales & CRM | Site-scoped leads, companies and shared marketing contacts; qualified-lead conversion, source routing, opt-in website/CSV inquiry intake, assigned due tasks and calendar downloads, deal stages, activity history and monthly forecasts by currency |
| Commerce and shipping | Site-scoped catalogs and variants, cart/checkout, orders, subscriptions, fulfillment, refunds, merchant payouts, upstream revenue terms, federated client sales and FedEx shipping integration |
| Books & accounting | Encrypted books, statement mapping/import, categorization, reconciliation and period controls, cash-basis P&L, Schedule C workpapers, supported native workbooks and reviewed-input federal estimates |
| People & Access | 26 default enterprise departments, reporting chains, HR/IT/finance separation, benefits elections, reviewed payroll statements, independent approval and employer-funded net-pay payout workflows |
| Identity and compliance | Authenticator MFA and recovery codes, OIDC linking, verified agency-to-client MFA, explicit resource grants, remote joining to existing AD/Samba AD domains and jurisdiction-source monitoring |
| Websites and community | Pages/sections, HTML design imports, starter designs, coordinated site themes, native store/journal integration, articles/RSS and per-site PWA branding, navigation and moderation |
| Communications | Lightek webmail, conversation replies, rich composition, mailbox management, distribution addresses, Junk/spam controls, mail templates and native transactional SMTP routing |
| Reservations and live rooms | Bookable resources, availability/capacity, paid reservations, calendar downloads, private guest rooms, host moderation and Studio program composition |
| Studio | Photo/video editing and exports; Blender authoring, modifier stacks and resumable CPU economy rendering, shots/storyboard, cast lip sync/body motion, materials/look; self-hosted Genesis concept images, text-to-video and image-to-video; music patterns, channel/group/master and effect automation, mixer inserts, audio takes, synchronized microphone overdub and punch ranges, instrument performance recording and picture scoring; saved live production setups, positioned graphic overlays and connected finishing/delivery workspaces |
| Infrastructure | New/existing server application installation, native Rails and container templates, GHCR image builds, domains/DNS, registered runtimes, targeted/fleet updates and installation receipts |
| Nevaeh speaking character | Private local spoken replies, stable 2D mouth animation driven by actual audio, pause/stop/replay and contextual Dashboard voice input; [guide](docs/nevaeh/tutorials/voice.md) |
| Nevaeh workforce & goals | 28 explained specialist roles, delegation/deletion, evidence-driven sequential goals, expansion workers and page-aware Dashboard assistance; [guide](docs/nevaeh/tutorials/workforce.md) |
| Graphical Nevaeh workspace | Persistent work tabs, script/blocking/embedded Studio, private correction rehearsals and a reactive Dashboard assistant; [guide](docs/nevaeh/tutorials/director_stage.md) |
| Character stories & spatial direction | Fictional personality templates, real cooperative story workers, limited character knowledge, pinned Cast identities, relative cameras/gaze, personal space and frame-sampled collision/depth checks; [guide](docs/nevaeh/tutorials/story_simulation.md) |
| Nevaeh | Task-focused conversational workspace with Studio/learning navigation, live receipts, sources, and consent controls; typed capabilities, structured tickets, agents/workers/schedules, change watchers, governed data console, Ubuntu application adapters, Digital Factory and native language-model training |
| Platform security and operations | Gatekeeper authorization, scoped Vault credentials, tenant ownership checks, background execution, audit history, retry/recovery paths and configurable Dashboard appearance |

See [FEATURES.md](FEATURES.md) for the detailed inventory, setup dependencies, current limits and module-specific evidence. Basic photo/video editing and advanced production paths use different editors and export contracts; their limits and payment requirements are documented separately.

## First production sign-in

A super admin without an enrolled authenticator is directed to **Sign-in security**. This is the expected enrollment step:

1. Enter the current Lightek password and choose **Set up authenticator**.
2. On your phone, open your authenticator and choose **Add account → Scan QR code**, then scan the QR shown by Lightek. No app needs to open on your Mac. If scanning is unavailable, expand **Can’t scan? Enter a setup key manually** for the time-based setup key.
3. Enter the current code and choose **Verify & enable**.
4. Save the ten one-time recovery codes privately, then continue to Dashboard. **Link organization sign-in** is optional and requires a separately configured organization provider.

The [sign-in guide](docs/security/sign-in-and-mfa.md) covers phone/desktop setup, subsequent login, failed codes, recovery and Connect handoffs. Keep setup keys, codes and passwords out of support tickets and screenshots.

## How the system works

The database holds operational state, ownership, registered capabilities and execution evidence. **Nevaeh** selects supported intelligence and operations; **Gatekeeper** enforces authority; **DymondDispatch** and registered workers execute; **Studio** is the creative and capability-construction workspace; **Dymond Bank** supplies the existing billing/payment integration. Tickets, KB procedures, receipts and artifacts make the work inspectable.

- Extend shared identity, sites, orders, billing and provisioning instead of adding parallel systems.
- Recheck ownership and permissions at execution, including delegated and scheduled work.
- Separate job submission, verified output, external settlement and actual deployment in receipts and documentation.
- Treat model-generated prose and imported documentation as reference/draft material; execution requires an authorized capability contract.
- Preserve historical evidence and surface blocked work rather than recording a success without an accepted result.

Architecture and target scope: [Product contract](docs/platform/product-contract.md), [Dymond control plane](docs/architecture/dymond-control-plane-v8.md), [ERP completion workstreams](docs/platform/erp-completion.md) and [historical architecture](docs/architecture/legacy-readme.md).

## Development and deployment

Use the versions and sources pinned by `.ruby-version`, `Gemfile` and `Gemfile.lock`: Ruby 3.3.6, Rails 8, PostgreSQL, Redis, Sidekiq, Active Storage/MinIO and the private ecosystem gems.

```sh
bundle install
bin/rails db:prepare
bin/rails zeitwerk:check
```

The standard production topology runs Rails natively under Apache Passenger. Docker supplies configured dependencies and isolated media runtimes; explicitly containerized application installations also have a supported adapter. Inspect `docker-compose.yml`, the deployment profile and existing environment before starting or rebuilding services.

Use **develop → release → main** for promotion. Run migrations and restart the relevant Rails, Sidekiq and Cable processes through the existing deployment pipeline. Use Customer Updates for selected installations, one account or a matching fleet; an update to the central app does not automatically prove that every independent client has received it. Preserve persistent data, environment settings and the original Vault wrapping key.

Operator references: [deployment integration](docs/lightek_deployment_integration.md), [fleet updates](docs/customer_fleet_updates.md), [storage](docs/deployment-storage.md), [mail operations](docs/mail/operations.md), [room activation](docs/studio/session-rooms-and-audience.md) and [Connect rollout](docs/integrations/lightek-connect.md).

Install Lightek Connect for WordPress directly from **Dashboard → Lightek Connect → Download WordPress plugin**, then upload and activate the ZIP in WordPress. The same screen manages pairing, Shopify app setup and isolated WordPress testing. Temporary connector outages preserve existing connections and offer retry. Real installation/client-management acceptance and marketplace distribution remain separate rollout checks in the Connect guide.

## Validation and release evidence

Run the relevant module's acceptance commands from its guide. The installed application's standard Rails checks remain available:

```sh
bin/rails test
```

Where installed, `bin/nevaeh-test` records invocation logs and JSON reports under `tmp/nevaeh/test_runs/`. Direct Rails invocations are not automatically recorded by that wrapper. Many standalone harnesses exercise real host models/controllers with explicit private-engine or external-provider boundaries; their scope is described in the corresponding guide.

The final PR #230 identity/bookkeeping/Connect acceptance passed **80 tests / 743 assertions on Rails 8.0.5 and PostgreSQL 16**. [Recorded CI run](https://github.com/Mrlightek/lightekmcg-site/actions/runs/43491056481). This is a specific release record, not a promise that all repository workflows or live providers are healthy. After deployment, repeat the workflow with the actual account, workers, runtime and provider configuration.

## Keeping the documentation current

Update [FEATURES.md](FEATURES.md) and the relevant operating guide when a feature or its acceptance boundary changes. Keep README as the entry point. Preserve older architecture/history as historical references; use the current feature catalog for product scope and the installed Nevaeh registry for executable command availability. Store capability contracts and verified procedures in the existing registry/KB alongside the documentation.

Agency wholesale pricing, reseller packages and installed feature limits: [operator and agency guide](docs/agency-reseller-packages.md).

Nevaeh’s spoken replies use an offline CPU natural voice with a stable style blend and private audio-driven mouth timing. The Studio image installs checksum-verified model assets and verifies stdin-to-WAV synthesis during deployment. Her activity label separates queued, running, delayed and approval/payment work; see [voice and activity guide](docs/nevaeh/tutorials/voice.md).

Spoken replies now start from private AAC playlist items as later items generate, using an authenticated HLS manifest and a separate single-slot voice queue. Status distinguishes queued from generating, abandoned queues fail after two minutes, and general help questions return a capability overview before documentation search. The playlist release requires the speech-segment migration and a Sidekiq restart.

Nevaeh can manage typed page-specialist tasks directly from the Dashboard assistant and shared stage: page/application inputs, named specialists, contract/manual drift checks, reusable assignments and actual downstream receipts. Pages without typed connections show their implementation gaps. See the [page-worker guide](docs/nevaeh/tutorials/page_workers.md).

**SME reports & lessons:** delegated workers retain structural execution reports and receipt-bound owner feedback. Nevaeh retrieves matching specialist/application/contract experience before new runs; available native conversational models can cite relevant reviewed lessons. See [worker reports](docs/nevaeh/tutorials/worker_reports.md). Requires the worker-report migration.

**Structured worker convention:** `/page TOPIC QUESTION` delegates to a one-page SME that rereads its source and returns exact excerpts. Every delegated run emits schema-validated JSON to the manager-owned account journal, with task/status/output/dependencies and explicit file ownership. See [Reporting System](docs/nevaeh/tutorials/reporting_system.md) and [JSON Schema](config/nevaeh/worker_report.schema.json). Requires `AddStructuredWorkerResults`.

### PWA membership and launch review

See [the November 17 PWA audit](docs/pwa_launch_audit_20261117.md) for current feature evidence, the Free → Personal → Business/Agency model, instance migration requirements, branded email and YouTube monetization limits. Creator offers, subscriptions, live gifts/tips, a full-principal support settlement ledger and central resumable YouTube publishing are now implemented with isolated database/API checks. Read [the launch acceptance runbook](docs/pwa_launch_candidate.md) before enabling them. Free accounts use shared hosting on one runtime per member server; paid upgrades transfer the selected account and originals to dedicated hosting. PostgreSQL isolation, scoped write holds and account import are covered by the shared-hosting acceptance suite. The operator controls admission, routing and prices. Production upgrade, billing and publishing acceptance remain separate from configuration readiness. Deployment, real payments/payouts, channel acceptance and external mail delivery are not established by these tests.

PWA revenue administration also offers **Teach Nevaeh**: prepare the PWA policy/audit as provenance-linked learning batches, review them, and train an enabled internal model through the existing sequential acceptance pipeline. See [the PWA business-model guide](docs/nevaeh/tutorials/pwa_business_model.md). KB synchronization and actual model-training status are reported separately; no missing executor is activated by learning the guide.

### Native 2D scenes and parallax

Studio opens **2D Scene & Parallax** independently of Genesis. A supported park prompt creates a seeded, editable layered scene; add prepared library images, change stacking and depth, animate assets/groups with reusable motion presets and editable position keyframes, save nested groups and render an H.264 preview. The CPU compositor uses FFmpeg and ImageMagick, without ComfyUI or Blender. Full exports reuse Dymond Bank checkout and can optionally include an editable, packed-texture Blender 2.5D project. See [scope, limits and acceptance](docs/studio/ai-studio.md#native-2d-scenes-and-parallax). Production PWA acceptance remains required after deployment.

**Performed Short** offers scene setups and production/saved-show launchers, then connects an illustrated reusable performer, a short dialogue recording or stock speech, phoneme mouth cues, a gesture and wide-to-close camera direction to a private three-second preview and existing paid export. Choose **Two-character dialogue** for two reusable performers, separate voices, two to four timed turns, silent listener reactions and alternating cameras in an up-to-eight-second CPU preview. Expand **Arrange performances into a sequence** to order and trim reviewed performances, preview a private cut, and build an editable Timeline from current full source exports. Guided facial cues, source-bound pointing and step-in entrances are available for new illustrated performers and compatible saved Cast. Prop interaction adds bounded hand reach, measured palm/wrist contact and an editable control-panel button response. Versioned character mechanics add a continuous walk/turn/sit/speak/stand bench performance with planted-foot solving, lap arms, measured seat support and pinned driver/source identity. See [scope and acceptance](docs/studio/performed-short.md).
