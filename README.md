# Lightek Media & Communications Group

**Lightek is a business operating system connecting websites, commerce, finance, people, communications, media production, infrastructure and automation in one Dashboard.** This repository is the Rails host application for that ecosystem and its client-facing experiences.

A business can build its website, sell products or book services, manage customer communications, produce media, run its own applications and delegate supported work to Nevaeh using the same accounts and operational records. Agencies can manage nested client businesses and independently provisioned client instances through the existing account, billing and Gatekeeper boundaries.

## Start here

| What you need | Where to go |
| --- | --- |
| The full current feature list | [Lightek feature catalog](FEATURES.md) |
| Production is asking you to set up an authenticator | [First sign-in, MFA and recovery](docs/security/sign-in-and-mfa.md) |
| Learn Nevaeh, agents, workers, watchers and commands | [Operating workspace and Guide](docs/nevaeh_operating_system.md) · [Tutorials](docs/nevaeh/tutorials/commands.md) |
| Edit a photo or video and export it | [Photo and Video Studio](docs/studio/open-source-editors.md) |
| Direct and render a shot sequence | [Shots & Storyboard](docs/studio/shots-and-storyboard.md) |
| Track Studio implementation and final verification | [Feature sprints](docs/studio/feature-sprints.md) |
| Group instruments and process the mix | [Mixer buses & inserts](docs/studio/music-mixer.md) |
| Automate the music mix | [Music automation](docs/studio/music-automation.md) |
| Compose reusable music patterns | [Patterns & playlist](docs/studio/music-patterns.md) |
| Finish Blender materials and scene look | [Look & materials](docs/studio/look-and-materials.md) |
| Arrange character motion | [Body motion clips](docs/studio/body-motion-clips.md) |
| Animate dialogue on a character | [Character speech & lip sync](docs/studio/character-lip-sync.md) |
| Set up a self-hosted generation worker | [Genesis workers & model packages](docs/studio/genesis-workers.md) |
| Create a website or publish articles | [Design & Content](docs/cms/site-themes-and-journal.md) |
| Configure books, people, payroll or company security | [Enterprise operations](docs/enterprise-directory-and-accounting.md) · [People and payroll](docs/people/organization-benefits-payroll.md) |
| Operate a server or update client installations | [Servers & applications](docs/server-application-management.md) · [Customer Updates](docs/customer_fleet_updates.md) |

These guides are also discoverable in **Dashboard → Software Library** after the updated repository is deployed. **Nevaeh → Guide** describes installed commands and capability availability. Access to each workspace still follows the signed-in account's permissions and feature entitlements.

## What is in the platform now

*Source snapshot: November 13, 2026, including merged PR #230. This describes implemented host workflows; it is not a claim that every external provider or every deployed client instance has passed live acceptance.*

| Workspace | Current capabilities |
| --- | --- |
| Business, agencies and Marketplace | Business overview, managed account hierarchies, client branding, products, billing versions, subscription intervals and reviewed fulfillment connections |
| Commerce and shipping | Site-scoped catalogs and variants, cart/checkout, orders, subscriptions, fulfillment, refunds, merchant payouts, upstream revenue terms, federated client sales and FedEx shipping integration |
| Books & accounting | Encrypted books, statement mapping/import, categorization, reconciliation and period controls, cash-basis P&L, Schedule C workpapers, supported native workbooks and reviewed-input federal estimates |
| People & Access | 26 default enterprise departments, reporting chains, HR/IT/finance separation, benefits elections, reviewed payroll statements, independent approval and employer-funded net-pay payout workflows |
| Identity and compliance | Authenticator MFA and recovery codes, OIDC linking, verified agency-to-client MFA, explicit resource grants, remote joining to existing AD/Samba AD domains and jurisdiction-source monitoring |
| Websites and community | Pages/sections, HTML design imports, starter designs, coordinated site themes, native store/journal integration, articles/RSS and per-site PWA branding, navigation and moderation |
| Communications | Lightek webmail, conversation replies, rich composition, mailbox management, distribution addresses, Junk/spam controls, mail templates and native transactional SMTP routing |
| Reservations and live rooms | Bookable resources, availability/capacity, paid reservations, calendar downloads, private guest rooms, host moderation and Studio program composition |
| Studio | Integrated miniPaint photo and Movie Masher video editors; saved projects and PNG/MP4 exports; advanced Blender, cast/performance, music, finishing, live production and delivery workspaces |
| Infrastructure | New/existing server application installation, native Rails and container templates, GHCR image builds, domains/DNS, registered runtimes, targeted/fleet updates and installation receipts |
| Nevaeh | Conversational operating workspace, typed capabilities, structured tickets, agents/workers/schedules, change watchers, governed data console, Ubuntu application adapters, Digital Factory and native language-model training |
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
