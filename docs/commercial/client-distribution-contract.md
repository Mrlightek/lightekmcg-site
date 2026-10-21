# Lightek-site customer distribution contract (draft)

## Product promise
Each customer buys a configured, version-pinned, separately deployed instance of Lightek-site on an isolated VPS. No bespoke fork or source reimplementation for each business. A device client can render only what its verified platform adapter supports.

## Default profiles
`config/lightek/deployment_profiles/{business,media}.yml` are inert data templates. `Lightek::Deployments::ProfileCatalog.fetch(name)` checks core safety invariants. They are NOT an installer, tenant seed executor or claim of production readiness.

## Planned lifecycle
Paid invoice -> durable authorized order -> Gatekeeper check -> provision VPS -> pin container digest -> inject per-tenant secrets -> migrate isolated DB -> idempotently seed profile pages/sections using real CMS APIs -> expiring admin invite -> verify health/TLS/backups/restore -> issue client configuration -> activate license -> issue receipt.

Never provision from an unverified webhook. Settlement and entitlement are separate state transitions; verify webhook signatures, provider events and idempotency keys. Never put Lightek's corporate data, private KB or master financial keys in tenant seeds.

## Money movement
Separate three ledgers:
1. Lightek service revenue (setup, licensing, hosting, management).
2. Client transaction proceeds / platform fees / refunds and reversals.
3. Payout payable and reconciliation for client's connected eligible payout account.

Clients configure a connected payout account through a supported payment partner; the payment partner handles compliant collection, split/transfer and payout where supported. Do not pool customer proceeds in Lightek accounts by default. Explicitly state merchant of record, fees, disputes, tax reporting and responsibilities before enabling payouts.

## CMS integration
Do not seed raw models until Dymond CMS or the actual page/section ownership API is inspected. Seed by stable slug and section key; preserve customer edits on upgrades; never destroy live content while updating defaults.

## Distribution and thin clients
Versioned Gatekeeper app config controls brand, modules, navigation, entitlements and screen descriptors. iOS/tvOS, Flutter/Android and Roku clients require separate validation/signing/distribution. No assumption that a thin client can bypass platform or app-store requirements.

## First proof
1. Read-only tests of profile catalog.
2. Discover canonical CMS page and section interfaces (likely engine or gem, not `app/models/page.rb`).
3. Build idempotent seed adapter backed by those interfaces.
4. Create single customer environment via approved Gatekeeper work order.
5. Verify backup/restore, customer isolation, payout-account boundary and versioned updates.
