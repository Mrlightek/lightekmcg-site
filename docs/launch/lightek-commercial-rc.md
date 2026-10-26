# Lightek Commercial Release Candidate — 2026-10-26

**Release objective:** Accept a paid Business customer, provision a usable business site and domain, and provide supported communications and social streaming tools. Tiffany's business is the first controlled pilot. This is a release candidate, not a claim that every bundle feature is production-ready.

## Product tiers and entitlement contract

| Tier | Monthly price | Included | Release rule |
| --- | ---: | --- | --- |
| Community | Free | Basic community access | Never grant paid domains, mailboxes, website provisioning, streaming, mobile or OTT from this tier |
| Business | $25 | Community, Lightek-hosted business site, domain setup/management, branded email, social-media streaming tools | Sell only when site, billing, domain and the specifically promised email/streaming capabilities have passed the pilot checks below; otherwise label unavailable capabilities as pending and obtain explicit customer acceptance |
| Media Network | $100 | Business, mobile/OTT distribution to Lightek standalone app and Roku Lightek channels | Do not publish for self-service purchase until app provisioning, branding, distribution and support are operational; consider a separately scoped pilot agreement instead |

**Future integrations, not currently included in a deliverable subscription:** Phone and internet services, and Netflix/Hulu or other external platform distribution. Third-party outlets require separate commercial delivery partners, rights, technical acceptance, and platform approval. Lightek should operate as the brand/aggregation layer, not promise guaranteed carriage. Domain registration/renewal and any third-party fees need explicit terms; don't imply an unlimited included domain.

## Release boundaries

- Lightek Mail PR #117 remains a separate merge and mail activation decision. Its global sending policy defaults to **off**. Merging does not create external SMTP capability, DNS or a mailbox subscription.
- Never activate customer paid access on a checkout preview alone; use the verified payment/settlement and entitlement/provisioning path. Keep manual fulfillment as a supported fallback only with an auditable order record.
- Do not change existing live Gmail settings merely by merging the mail PR.
- Preserve per-customer website/domain isolation and reject unknown hostnames. Verify the selected site identity after provisioning.
- Mail and streaming tools may be sold only when live tests confirm the exact features promised in the customer's contract.
- Never convert a free membership to a paid account without confirmed order/payment and clear consent.

## Tiffany pilot: acceptance checklist

- [ ] Create a private, customer-specific Business Marketplace draft at $25/month; verify Dymond Bank checkout preview shows exactly $25 recurring and disclosed upfront charges.
- [ ] Perform a **test** transaction through the configured Stripe/Dymond Bank path and verify webhook/payment state, subscription state, order record and idempotent provisioning (no duplicate site).
- [ ] Confirm her approved business name, desired domain, content/assets, and account owner before provisioning.
- [ ] Provision a Lightek site through the existing website flow, verify HTTPS, unknown-host rejection, ownership isolation and public pages from an unauthenticated browser.
- [ ] Verify editing theme, headings/Google Fonts, navigation, contact form and mobile layout, including a customer login with no access to another customer's assets.
- [ ] Verify domain ownership and DNS; disclose the actual domain registration/renewal price before charging it.
- [ ] For email: only enable the mailbox after Postfix/Rspamd, inbound routing, DNS SPF/DKIM/DMARC/PTR, TLS, bounce/complaint feedback and real test sending/receiving pass. Otherwise make email a clearly disclosed pending feature and do not charge for an unavailable fully bundled service without Tiffany's agreement.
- [ ] For social streaming: validate at least one actual connection and publish flow with customer-authorized accounts; do not imply unsupported Restream/social network endpoints work.
- [ ] Have Tiffany approve the site, a real invoice, support contact, cancellation policy and service scope; capture a first successful payment and fulfillment receipt.
- [ ] Roll out publicly only after the pilot has a repeatable payment, provisioning, rollback, and support procedure.

## Release sequence

1. **Freeze scope:** Community and Business are priority; Media Network is a controlled preview. Do not add phone/internet or external OTT partner features to the initial launch.
2. **Finalize PR #117:** native integration or equivalent production-like test evidence for mail features; keep actual mail delivery paused until infrastructure is validated. CI configuration by itself is not a blocker.
3. **Launch site pilot:** test existing marketplace, subscription and Dymond V8 website flow on a staging environment; fix failures and repeat.
4. **Fulfill Tiffany pilot:** generate a scoped $25 Business order, verify payment, provision her actual website and domain, demonstrate account ownership isolation, and capture acceptance.
5. **Activate mail/social individually:** only after each feature meets its live acceptance test and Tiffany agrees to any temporary exclusions.
6. **Open to more customers:** publish only the verified offering, with accurate inclusions and disclosed external charges. Continue shipping features without breaking existing subscriptions.

## Evidence record

For each test, record environment, timestamp, code SHA, customer-safe test account, expected/actual result, and operator. Attach relevant receipts and logs without sharing credentials. **No customer payment, production provisioning, external email, or Netflix/Hulu distribution is asserted by this document.**

## Ownership

Product tiers and pricing are the founder-approved business direction as of 2026-10-26. This document sets release criteria, not a fabricated claim of a completed deployment.
