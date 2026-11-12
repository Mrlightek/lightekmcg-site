# Integrated platform operations

Lightek's product direction is an ERP built into the platform: customer and agency identities, storefront products, purchases, subscriptions, hosting, shipping and settlement share the existing accounts and order records. A purchase should carry its ownership and agreed terms through fulfillment without being re-entered in another tool. This implementation connects those operations; it is not a complete accounting, payroll or procurement system.

## Dashboard workflows

| Task | Entry point | Result |
| --- | --- | --- |
| Install the application on a new server | Servers & applications → Install application (super admin) | Creates a provider request and installs a native Rails application or selected container template, then records the installation receipt. |
| Add a website to an existing server | Server → Add website / Install application | Uses the selected node and authorized managed owner; hostname, capacity and ownership are checked before dispatch. |
| Sell hosting at retail | Hosting packages → package configuration, then customer hosting checkout | Provider plan, cost ceiling and margin remain operator configuration. The customer buys the retail product. The payer and installed application's owner are recorded separately. |
| Manage an agency | Agencies → enable agency / create client / branding / revenue terms | Uses nested managed accounts, inherited branding and explicit upstream revenue terms. Existing purchase snapshots retain their agreed terms. |
| Run a store | Commerce → products, orders, subscriptions, fulfillment and payouts | Uses the existing site-scoped products and orders. Service products can bill monthly/yearly; inventory rules are captured when the order is reserved. |
| Ship a parcel | Shipping → origin and packaging → rates → purchase → label / tracking | Uses the platform carrier connection and retail shipping price. Merchant screens do not receive the carrier credential or base cost. |

A client instance connects through the existing authenticated federation peer. Merchandise checkout goes to the platform processor account; receipts are synchronized back to the client instance. Each peer's mirrored merchant tree is confined to that peer's reseller branch. Refund, fulfillment, payout and subscription-cancellation requests address only that peer's sales. Renewals retain their invoice identity and receive subsequent fulfillment, refund and payout updates. A browser return from checkout is not payment confirmation.

## Configuration and deployment

1. Deploy to the platform and client instances that will use network commerce; apply migrations `20261112070000`, `20261112073000`, `20261112080000` and `20261112083000`. Restart Rails and queue workers, and apply the existing scheduler configuration. The migrations extend existing commerce records and add agency, hosting, subscription, revenue-allocation, shipping and federation settlement records.
2. Configure an enabled application template and provider connection. The default native Rails template installs the Lightek application; a container intended to run Lightek must explicitly enable the Lightek application option so owner/bootstrap/runtime registration runs.
3. Configure retail hosting packages as super admin. Provider prices are checked against the purchased package's ceiling at provisioning time. No server creation should be treated as verified merely because its provider allocation succeeded: application, HTTPS and owner access need their receipt checks too.
4. Configure the existing Stripe connection, signed webhook endpoint and Stripe Tax setup. The integration routes checkout, invoice and subscription lifecycle events through the existing commerce handler. Exercise initial payment, duplicate delivery, renewal, payment failure and end-of-period cancellation in test mode before live acceptance. Merchant transfers retain the existing `LIGHTEK_COMMERCE_MERCHANT_TRANSFERS_ENABLED` reconciliation gate and Connect onboarding requirement.
5. For client instances, preserve or establish the existing federation configuration and Vault peer token. The automatic installer passes this connection to new paid instances. Older instances need the existing federation connection operation; merely installing this code does not establish a missing peer connection.
6. In Shipping, super admin configures the platform FedEx API credentials/account in Vault, retail markup/minimum margin and sandbox/production mode. Merchant sites configure their own origin and parcel dimensions. FedEx and Stripe modes must agree. Production shipping remains explicitly disabled until approved in carrier settings.

FedEx coverage in this release is domestic U.S. parcels, PDF labels, tracking and cancellation. Rates expire; changed carts require a matching new quote. Label purchase requires a confirmed paid order. A timeout after shipment submission is recorded for review instead of blindly purchasing another label. Carrier cancellation and payment refund are separate operations. International customs, freight, pickups, negotiated carrier-account eligibility and actual carrier billing adjustments are not proven by mocked tests.

## Verification and limits

The standalone suites exercise real Active Record models, transactions and migrations while replacing cloud, processor and carrier calls at their boundaries:

```sh
ruby test/standalone/commerce_network_test.rb
ruby test/standalone/website_deployment_dispatch_test.rb
ruby test/standalone/hosting_bootstrap_test.rb
ruby test/standalone/fleet_hosting_test.rb
ruby test/standalone/fleet_application_launches_test.rb
python3 -m unittest discover -s test/standalone -p 'fleet*_test.py'
```

`commerce_network_test.rb` also loads the commerce/hosting suite. It checks checkout reuse and frozen terms, hierarchical access, retailer margins, recurring event handling, revenue allocation and reversals, shipping quotes/labels with provider doubles, network purchase identity, redirect boundaries and repeated renewal synchronization.

Live cloud installation, actual FedEx sandbox/production requests, Stripe test-mode settlement across two independently running instances, and authenticated full Dashboard browser acceptance remain release acceptance work. Passing local contracts is not proof of those operations. Do not label the entire ERP finished based on this PR.

Provider references: [Stripe subscription webhooks](https://docs.stripe.com/billing/subscriptions/webhooks), [FedEx Ship API](https://developer.fedex.com/api/en-us/catalog/ship/v1/docs.html).
