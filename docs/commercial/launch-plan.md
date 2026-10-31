# Lightek commercial foundation — October 2026

## Operating premise
Lightek MCG is the parent operating/holding-company identity. Enterprise Solutions is the first commercial focus. Lightek-site is intended to be a reusable, deployed customer product, not a custom rebuild per client. Organizational isolation, controlled module enablement, and license/updates must be proven before offering turnkey deployments.

## Customer deployment contract (proposed, not implemented)
1. Lead -> scoped proposal -> signed agreement -> paid/settled invoice.
2. Record customer organization and immutable deployment request. Require independent approval and a corresponding work order.
3. Gatekeeper validates entitlements, domain, compute profile, cost ceiling, security policy, and authorization.
4. Provider adapter provisions a VPS with immutable image/container build and secrets delivered via secret manager.
5. Bootstrap Lightek-site in single-organization mode; seed defaults using idempotent versioned profile; create first admin via expiring invite.
6. Verify TLS, DNS, health, background workers, backups, restore test, and device configuration API.
7. Register tenant license, version, deployment artifacts and audit trail. Deliver credentials using secure channel.
8. Update through pinned releases and rollback mechanism. Each client database and object store must be isolated.

Do not mount internal Lightek corporate datasets, Nevaeh private KB, platform billing credentials, or cross-client access in customer VPSes.

## Thin-client contract
Common versioned JSON delivered via Gatekeeper: app/brand configuration, authenticated identity, navigation, layout, content rails, allowed actions, feature flags, cache TTL, API endpoints. Platform adapters: web, iOS, tvOS, Android/Flutter, Roku SceneGraph. Validate per-device limitations; no assumption that standard apps can override carrier voice/APN settings.

## Marketing factory concept (proposed)
Campaign brief -> Nevaeh checks KB/brand policies -> Studio composes original copy/storyboard/media -> approval -> exports -> platform-specific publishing -> evidence/analytics -> feedback/ticket.
Gatekeeper gates publication and account access. Do not assert autonomous video creation or connected social posting until integration tests and actual executions pass.

## First campaign
- Corporate message: The infrastructure behind digital independence.
- Enterprise message: Your business. Your platform.
- Media message: Stories deserve an infrastructure of their own.
- Proof content: platform architecture walkthrough; client install demonstration after verification; how policies route from Nevaeh to Gatekeeper; Octavia connected-TV demo.
- CTA: scoped consultation and proposal; existing /contact route.
- Channels: LinkedIn for B2B, YouTube for technical proof, Instagram/TikTok for media teasers, direct outbound for near-term revenue.

## Launch gates
- Public pages reviewed for accuracy and functional links.
- Contract/SLA/pricing review and collected payment proof.
- Isolated VPS acceptance test with clean installation, backup/restore, security isolation and update rollback.
- Device client compatibility verified independently for each platform.
- Studio-generated campaign assets reviewed by a human for accuracy, originality and rights.
- Publish only after approval and audit record.

## 2026 milestones (targets, not guarantees)
- October 21–31: commercial pages + canonical offer + marketing briefs.
- November 1–15: reusable client deployment installer, license/default profile, automated acceptance checks.
- November 16–30: first paid pilot and verified multi-device demonstration if client readiness permits.
- December 1–20: repeatability, customer references, recurring billing and support operations.
- December 21–27: planned vacation operational handoff, health alerts, emergency support and cash-flow review.
