# One Lightek operating platform

The product goal is a complete ERP and accounting suite built around Dymond Bank. LightekMCG's business, communications, creative and infrastructure capabilities belong to one operating system. A user should recognize the same navigation, customer identities, permissions, terminology and transaction history in every workspace.

| Workspace | Intended capability | Shared foundation |
| --- | --- | --- |
| Business and accounting | Customers, suppliers, quotes, invoices, receivables/payables, double-entry accounting, reconciliation, reporting, tax configuration, purchasing, inventory, workforce and business operations | Dymond Bank, existing accounts, orders, billing and settlement records |
| CMS and commerce | WordPress-class page/section/design authoring integrated with Shopify-class catalog, storefront, checkout, subscriptions, fulfillment and merchant tools | The same site, theme, customer, service and product records; products and bookings usable directly in page composition |
| Cloud and hosting | A native Dashboard cloud console combining WHM/cPanel-style account/hosting operations with GCP-style infrastructure management: instances, applications, domains, DNS, email, databases, storage, backups, deployments, usage and billing | Existing Gatekeeper provisioning, managed account hierarchy, Vault, fleet updates and Dymond Bank |
| Communications and reservations | Mail, calendar, bookable services, voice/video rooms, guest management and appointments | Existing identity, site, service, booking, availability, order and payment records |
| Studio and broadcasting | Editing, animation, AI media, music, guest production, professional stages, delivery and audience management | The same asset library, rooms, authenticated accounts, publications and commercial entitlements |

These are capability and experience targets, not a statement that each is complete. Completion requires executable workflows, reliable failure/recovery paths, appropriate permissions and acceptance evidence. Existing services must be extended rather than replaced by parallel billing, identity, booking or provisioning systems.

## Interaction rules

- Keep site/account context through breadcrumbs, forms, redirects, room links and Studio handoffs.
- Give people task-based starting actions. Separate ordinary work from infrastructure configuration and advanced engine options.
- Keep forms and drafts intact when validation fails or background data changes.
- Show setup and connection status at the action that needs it; a saved credential is not a verified connection.
- A paid booking uses the existing price, order and verified payment path. A private production room has no fake reservation, order, revenue or accounting entry.
- Room guests, community audiences and external-platform commenters are distinct identities. Do not invent viewer names or aggregate overlapping counts.
- Make operational records traceable to their existing business transaction. Verify ledger posting and reconciliation separately before claiming complete accounting coverage.

## Current implementation boundary

The Reservations/Rooms/Live workflow change adds direct private production rooms, preserves paid booking access, improves bookable-service setup and validation, retains site context, exposes usable stage presets and makes audience adapters discoverable. It does not complete the full ERP/accounting, CMS/commerce or cloud-console targets above, nor establish live carrier/social/media acceptance.

## Business creation and distribution loop

Studio is a native Dashboard media-production workspace for business owners as well as filmmakers. The DaVinci Resolve reference defines the connected editing/color/effects/audio/delivery experience; the Lightek-specific workflow also connects branding, products, campaigns, live guests, AI/Blender authoring and business operations. Keep the same production and source media through those tasks instead of manufacturing unrelated assets per tool.

The intended distribution loop is Studio → CMS page/campaign → the business's PWA/Lightek channels and connected social destinations → later Roku/OTT releases from the same catalog. Existing destination adapters and entitlement checks still apply; a destination appearing in the interface is not proof that a real account publication succeeded.

A PWA belongs to a provisioned website/application. The hosted-site installer currently creates its `LightekPwa::Application` record, and Dashboard PWA Administration manages the selected site's brand, navigation, content and features. Creating a user login alone does not provision an independent website/PWA. The business-account onboarding goal must include that application lifecycle explicitly.

Reference: https://www.blackmagicdesign.com/products/davinciresolve

## CMS and journal delivery

Design & Content now puts Pages & Sections first and separates the working tools from the collapsed design library. Site-theme bundles coordinate installed designs or multiple HTML uploads, shared chrome, real navigation, native store/cart/checkout sections and the website journal. Website articles share their canonical `Post` body/author with PWA/community publication; draft/archive state, per-site URLs and editor conflicts remain explicit. See `docs/cms/site-themes-and-journal.md` for workflows, deployment and acceptance boundaries.
