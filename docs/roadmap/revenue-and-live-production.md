# Lightek Revenue Activation & Live Production

**Planning snapshot:** 2026-10-23. Not a representation of deployed functionality.

## Release priority: sell and fulfill

### V8.6: Control-plane reliability

- Standardize sitewide administrative authorization and program/tenant-aware memberships across Rails host, Dymond Dash and Nevaeh.
- Inventory actual 403-producing filters and their policy owners; permit super-admin inspection without bypassing enforcement requirements.
- Add individual DymondBank subscription administration in Dymond Dash with user/customer assignment, service status, lifecycle controls and audit evidence. Reuse existing Dymond Bank callbacks/services, not parallel billing logic.
- Introduce configurable `partner` role and `plp` partner-program memberships; keep client entitlements composable.
- HTTP regression coverage for super-admin access, partner scopes, customer isolation, and denied execution.

### Paid website release

- Confirm order/payment settlement once, with provider callbacks verified and deduplicated.
- Authorize and persist a provisioning request, create a tenant Dymond Site and default subdomain, publish minimal valid content and link to dashboard.
- DNS and HTTPS automation through existing registrar/network execution services.
- End-to-end receipt: paid order, service, DNS/HTTPS health, tenant separation, support ticket on verified failure.
- Retain domain-only and website/domain attachment flows. Extend to mobile/OTT bundles without delaying the basic website release.

## App builds and distribution

Keep one build-request contract with interchangeable local and hosted builders. Android supports properly signed, self-hosted test APK distribution; Apple iOS test installation and external distribution remain subject to Apple signing and provisioning eligibility. Xcode Cloud/App Store Connect integration is a future build-provider switch when the developer account is active, not a replacement for Gatekeeper-driven app configuration.

## LIVE production and marketing

Objective: present Lightek development sessions as a real-time production using Lightek's own Studio and Gatekeeper-linked infrastructure, while also creating a marketing and monetization channel.

1. **First broadcast:** capture desktop/camera/microphone with production-grade scene switching, overlays, titles, audio monitoring and local recording; output a standard ingest stream with health diagnostics.
2. **Social platform output:** add destination profiles, credential authorization, provider-specific ingest/API adapters and stream/session controls. For TikTok LIVE, confirm current account eligibility and permissible desktop/encoder workflows before automating publication; do not assume an unrestricted public third-party live-creation API.
3. **Operations:** per-destination stream health, failover/reconnection, key rotation, recordings, clips, moderation, and incident tickets.
4. **Later product offering:** customer-managed live channels, multistream subscriptions, OTT playback and analytics through the same Dash + Bank + Nevaeh + Gatekeeper lifecycle.

The first LIVE demo should be useful before the entire future multistream product exists. Maintain separation between media ingest, transcoding, distribution, publishing permissions, and customer billing.

## Acceptance definition

A feature is **live** only after its authenticated customer path, billing/authorization, deployed execution, monitoring and rollback are actually verified. Tests and documentation alone are not evidence of live fulfillment.
