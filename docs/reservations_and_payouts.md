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
3. For a server resort package, the platform super admin selects an existing server product/subscription plan, provider plan/region/image, actual monthly infrastructure cost and a protected full-term cost-plus-margin floor. The price must cover that floor plus the configured fee reserve, including a conservative 25% tax allowance for USD storefront processing. Checkout also compares the selected plan's provider catalog price against the configured cost estimate.
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
- The worker reconciles the existing Linode plan, requests a resize when needed, waits for the target plan to run and the provider resize event to finish, applies the subscription and reservation manifest through the registered native Rails transport, and verifies the returned change/reference receipt before completing the central entitlement update. Resizing may restart the server. Provider disk-size restrictions remain enforced by Linode; no destructive disk shrinking is attempted.
- Failed paid changes remain visible in Dashboard and can resume against the same order/server. A receipt from an accepted resize alone never marks accommodations active.

## Reservations across independent client servers

Each newly provisioned client receives an opaque, revocable peer connection. The central database retains the peer token digest, merchant identity, approved infrastructure packages, server reservations and payment orders. The client stores its scoped token in its own Vault; its site manifest contains only the central origin, peer key and Vault reference. Provider credentials, platform Stripe secret keys and bank account numbers are not delivered by this connection.

The client Dashboard adds a server-resort network page. A merchant can publish offers using centrally approved packages and any installed industry experience. Prices must cover the protected platform floor and fee reserve; ownership, cloud configuration, subscription IDs and payout destinations cannot be supplied by a peer request. Public booking pages display the merchant's network offers alongside local appointments.

Checkout redirects to the central Lightek account and requires the buyer to sign in or register there. A signed-in central account claims an expiring, idempotent checkout intent. A remote server cannot take over an existing central account by supplying an email address. Network reservations remain visible from the client's My Reservations page, with central management and upgrade links.

Bank-account onboarding and destination changes take place in the central merchant account. The peer API can adjust only its own weekly/biweekly earnings-release preference. Existing configured storefront payment flows are retained: only the public Connect account identifier and payout schedule are synchronized to the local merchant. Neither synchronization nor the peer API copies a bank account number or platform secret key.

For an existing registered native client, first deliver the updated application through the existing update pipeline, then use **Application installations → Connect reservation network** as the platform super admin. The connection installer validates the remote site owner and stores the peer credential in the remote Vault. A connection receipt must match the issued peer before success is reported.

## Native and Docker applications

The existing **Servers & Applications → Applications** launcher supports both native Rails and Docker image templates on existing or newly allocated servers. Its Docker path can run Rails, Sidekiq, PostgreSQL and Redis as a Compose stack. Image builds accept a repository branch and produce a registry image pinned by digest.

The paid server-reservation path in this release uses native Rails/Passenger, with Docker dependencies. Automatically selecting the Docker launcher for paid reservation packages is a separate runtime-adapter extension; industry website templates do not change the installation runtime. Existing instances are not migrated between runtimes by booking or package changes.

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
# ActiveRecord, actionpack and railties 7.2 or 8.0; sqlite3; minitest; stripe 19.6.2
ruby test/standalone/reservations_http_checks.rb

# Real HTTPS between separate central/client database processes; requires webrick
ruby test/standalone/reservation_federation_checks.rb

# Real PostgreSQL row-lock contention, plus the same functional/HTTP checks
RESERVATIONS_DATABASE_URL=postgres://USER:PASSWORD@HOST/reservations_test \
  ruby test/standalone/reservations_concurrency_checks.rb
```

The dedicated reservations acceptance workflow provisions PostgreSQL 16 and Ruby 3.3.6. Tests exercise production models, services, routes and views with controlled adapters for private engines, email, Stripe and cloud requests. Full host boot, real Stripe transfers, live resizing and delivery to an installed client require the configured integration environment; isolated tests do not claim those production actions occurred.

## Configured release gates

The dedicated release workflow uses an isolated checkout and a uniquely named temporary PostgreSQL database on the configured server. It reuses installed private dependencies, boots the actual Rails engines, migrates the temporary database, exercises the real Vault and Stripe SDK, verifies signed webhook settlement and provisioning enqueue, and removes the temporary database afterward. Production application code and schema are not deployed by these checks.

Live service checks are separate: a single $1 Stripe verification checkout is retained for PR 201 across source revisions, and a newly labelled/tagged Linode is allocated, resized up, resized back down, and removed. Existing client nodes are never resize targets. The resize gate requires a completed provider event; a plan value changing in an API response is insufficient. The final payment gate remains pending until a person completes the live checkout and Stripe confirms the PaymentIntent succeeded. A created checkout is not evidence of a paid transaction.
