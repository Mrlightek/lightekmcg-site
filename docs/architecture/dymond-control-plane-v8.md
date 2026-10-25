# Dymond V8: Unified Service-Provider Control Plane

**Status:** architecture and implementation roadmap, updated 2026-10-23. This document does not assert production readiness.

## Origin and ownership

This is Lightek MCG's existing, user-established architecture, not a proposal to fragment the ecosystem into new applications. Lightek is one integrated Rails-hosted ecosystem with modular engines and service boundaries. cPanel, Active Directory and WHMCS are *functional inspirations*, not applications to embed or independently reproduce.

## Operating model

- **Dymond Dash:** unified administrative and customer control plane for users, account relationships, purchased services, subscriptions, domains, websites, infrastructure, tickets, and partner access.
- **Dymond Bank:** financial source of truth for checkout, invoices, payments, subscriptions, and settlement.
- **Nevaeh:** evaluates intent, knowledge base policies/procedures, available intelligence, and unresolved cases. Creates trouble tickets when procedures cannot handle a condition; verified resolutions update institutional knowledge.
- **Gatekeeper:** enforces identity, authorization, policy and execution boundaries. Distinguish permission denial from capability unavailable and job failure.
- **DymondDispatch and service executors:** execute authorized work, record evidence, handle retries/idempotency, and report results.
- **Dymond Site / Dymond Compute / Registrar and GoDaddy:** existing specialized implementations serving tenant websites, compute/network resources and domain operations.
- **Mobile and OTT thin clients:** shared client codebases render experiences using authenticated Gatekeeper-delivered configuration and content. Artifacts are built and distributed through platform-compliant channels; build providers are swappable.

## Identity and access model

Roles: `super_admin`, `admin`, `employee`, `contractor`, `client`, and **proposed** `partner`.

- `super_admin` can administer platform resources across tenants and inspect policy status. It must not bypass external provider requirements, execution-environment restrictions, financial settlement or immutable security/audit conditions.
- `admin` is delegated and account/organizationally scoped; avoid global `manage :all` for ordinary admins.
- `partner` is a role with membership in configurable programs, initially `plp`. Program capabilities and partner-account delegations are separate from purchased customer entitlements.
- A user's identity, tenant/account memberships, capability grants and subscription entitlements are distinct dimensions. Do not encode all combinations as hardcoded roles.

Audit HTTP and engine boundaries across Rails host, Dymond Dash and Nevaeh for `head :forbidden`, `render ... :forbidden`, CanCanCan `authorize!`, feature checks, local opt-in checks and Gatekeeper decisions. Read-only inspection should not require execution opt-in. Authorization and execution-policy evaluation must remain separately explicit, tested boundaries. Do not globally suppress 403 responses.

## Commercial lifecycle

**Customer selects service → order and payment → confirmed settlement → Nevaeh procedure → Gatekeeper authorization → provider/service execution → verification → Dash visibility and continued billing/support.**

Supported purchase intents:

1. Domain only.
2. Website only (Lightek-managed subdomain by default).
3. Domain plus website.
4. Domain attached to a previously purchased website.
5. Website plus mobile/OTT thin-client products, with domain or platform add-ons as offered.

Distinguish **product plan**, **individual subscription**, **payment record**, **provisioning request**, **provisioned service**, **domain registration**, and **tenant account**. Provisioning must be idempotent, account-scoped and retry-safe. A canceled subscription is not a deleted subscription; archival, refunds, termination and domain renewal are separate lifecycle events.

## Verified versus pending

As of the latest user-reported local tests, V8.4 planning and V8.5 website-creation code pass focused tests; **paid checkout-to-live-site fulfillment has not been demonstrated**. Local installations and proof tests are not production deployment. DNS, Apache/TLS, completed payment-triggered activation, individual subscription CRUD in Dash, sitewide super-admin HTTP acceptance coverage, and partner/PLP membership execution require implementation and verification.

The host's README implementation table remains its own dated evidence snapshot; do not silently reinterpret it as deployed capabilities.
