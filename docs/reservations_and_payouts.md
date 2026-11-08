# Lightek reservations and server resort

The host reservation layer composes the existing Dymond Booking registration, Commerce orders, Dymond Bank Stripe integration, Gatekeeper allocation/owner access, industry starter library, and native application update transport. It does not replace payment processing or add a second checkout processor.

## Entry points

- Dashboard → Reservations & Experiences: site-scoped calendar/day agenda, resource/package editor, opening hours, buffers, capacity, front-desk bookings, check-in/completion, blocked dates, and failed package-change recovery.
- `/reservations`: the current hostname's published experiences. A site owner may preview their own site with `site_id`. Public visitors cannot browse another tenant's catalog by changing the ID.
- `/my/reservations`: the signed-in customer's reservations, checkout, calendar download, cancellation/rescheduling, and server package renewal/change quotes.
- Commerce → Merchant payouts: Stripe Connect bank-account onboarding plus weekly/every-14-days earnings-release preferences. A reservation link is also available from My Applications and the client instance's Dashboard sidebar.

## Set up experiences

1. Create a digital service product for priced appointments, meetings, voice/video calls, live sessions, equipment or venues. Inventory is controlled by Commerce; set enough stock for the intended offering. Complimentary appointments do not require a product.
2. Create a reservation experience in Dashboard and choose its product, duration, capacity, timezone, notice, cancellation window, buffers and opening hours. Leave all hours blank for flexible booking. Add a location or HTTPS session URL. The session URL appears only on an authenticated, confirmed guest reservation.
3. For a server resort package, the platform super admin selects an existing server product/subscription plan, provider plan/region/image, actual monthly infrastructure cost and a protected full-term cost-plus-margin floor. The price must cover that floor. Checkout also compares the selected plan's provider catalog price against the configured cost estimate.
4. White-label operators select a published platform-approved infrastructure package. Its compute configuration, billing interval, subscription plan and minimum protected floor cannot be overridden. They can set their own price above the floor, brand the offer, and select any installed industry starter.
5. Publish the experience. A booking is a snapshot: later catalog edits do not rewrite the customer's purchased rate or accommodations.

## Booking and allocation

Resource row locks serialize capacity claims. Capacity is calculated from simultaneous overlaps, including saved buffers; adjacent reservations do not overlap. DST gaps and ambiguous local times require a different time or an explicit ISO 8601 offset. Prices and end times are calculated on the server.

Priced appointments hold capacity and Commerce stock until the existing signed webhook confirms payment or checkout expiration is verified. A local clock alone never releases an unresolved Stripe session. Expiry recovery runs every five minutes. Email receipts and reminders use the existing application mail delivery; a calendar file is available without exposing the private session link.

A paid server reservation uses the existing order-bound Gatekeeper allocation and secure owner-password handoff. Allocation waits until the reserved start time. The selected industry starter becomes the client's editable, published homepage. The remote instance receives its paid subscription plan and a central reservation-management link; customer edits are preserved on subsequent package changes.

The three-day unpaid renewal grace period pauses the server without deleting it or its data. **A paused Linode still incurs provider infrastructure charges.** The platform's retained cost/margin reserve covers the purchased term; operators must resolve delinquent accounts and retained-storage costs through the existing infrastructure workflow. No automatic destructive deletion is introduced.

## Package changes

- Upgrades credit only the remaining value of the originally contracted rate. Integer rounding never undercollects a fractional cent. If a prorated charge would be below Stripe's USD minimum, the offer becomes a full prepaid next-term renewal instead.
- Downgrades reserve and pay the next term at the lower rate; the current paid term receives no automatic cash refund. Renewing an expired reservation buys a fresh full term from the new effective date.
- Quotes expire after 30 minutes and are accepted once. One in-progress change prevents conflicting purchases. Billing-interval, region and operating-image changes require a new reservation.
- Change orders have `purpose=reservation_change`; they never allocate a second VPS or decrement server-product inventory. A verified payment schedules the change.
- The worker reconciles the existing Linode plan, requests a resize when needed, waits for the target plan to run, applies the subscription and reservation manifest through the registered native Rails transport, and verifies the returned change/reference receipt before completing the central entitlement update. Resizing may restart the server. Provider disk-size restrictions remain enforced by Linode; no destructive disk shrinking is attempted.
- Failed paid changes remain visible in Dashboard and can resume against the same order/server. A receipt from an accepted resize alone never marks accommodations active.

## Merchant earnings

Customer charges continue to enter the platform Stripe account. Merchants add their payout bank account through the existing Stripe Connect onboarding; Lightek does not collect bank account numbers.

A durable per-merchant schedule defaults to **14 days**, optionally **7 days**. An hourly recovery worker releases eligible fulfilled-order earnings using the existing transfer service. Bank arrival is controlled by Stripe settlement and the connected account's bank payout settings; the selected Lightek cadence is the platform-to-Connect earnings release, not a guarantee of a bank deposit on that date.

Existing `LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED=true` reconciliation control is retained. Stripe Connect readiness, pending refunds, positive net amounts and verified paid fulfillment are required. Errors retain the due run for retry; completed order transfers are idempotent. Super-admin visibility across sites does not grant ownership of another merchant's earnings. Server orders retain the purchased infrastructure-plus-margin floor before merchant transfers, in addition to the existing fee reserve.

New Stripe Checkout and transfer idempotency keys include a saved site namespace: separate client databases can both have order #1 while using the same platform Stripe account. Signed webhook events with another namespace are acknowledged without settling local orders. Legacy orders retain their original recovery keys.

## Deployment and validation

Run `bin/rails db:migrate`, deploy the application/assets, and restart the existing Sidekiq worker so its cron schedule loads the reservation and payout sweep jobs. Existing installation/provider, Vault, Stripe and mail configuration still applies. `LIGHTEK_RESERVATION_ORIGIN` defaults to `https://lightekmcg.com`; set it to the central account-management origin for another deployment.

No packages are seeded with invented prices. Publish your actual Commerce offerings and approved infrastructure packages from Dashboard.

Isolated checks (no private engines, Stripe calls or paid cloud allocation):

```sh
# ActiveRecord, actionpack and railties 7.2 or 8.0; sqlite3; minitest
ruby test/standalone/reservations_http_checks.rb

# Real PostgreSQL row-lock contention, plus the same functional/HTTP checks
RESERVATIONS_DATABASE_URL=postgres://USER:PASSWORD@HOST/reservations_test \
  ruby test/standalone/reservations_concurrency_checks.rb
```

The dedicated reservations acceptance workflow provisions PostgreSQL 16 and Ruby 3.3.6. Tests exercise production models, services, routes and views with controlled adapters for private engines, email, Stripe and cloud requests. Full host boot, real Stripe transfers, live resizing and delivery to an installed client require the configured integration environment; isolated tests do not claim those production actions occurred.
