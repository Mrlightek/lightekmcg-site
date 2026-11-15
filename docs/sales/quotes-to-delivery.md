# Catalog quotes → orders → payment → delivery

Open a deal in **Sales & CRM**. **Prepare a catalog quote** connects the existing sales relationship to the existing Commerce order/payment/fulfillment path. A manually won deal uses the same quote/approval flow; changing its stage alone never creates a charge or order.

## Prepare and issue

Select quantities from this website's published service, digital-product or managed-installation catalog. Enter customer email, scope/delivery terms and an expiry date. Save the draft, review it, then choose **Issue quote**.

The first connection supports USD and existing catalog prices. Physical/shipping quotes, variants, custom negotiated line prices, discounts and mixed subscription baskets are not supported by this quote form. Subscriptions and managed installations require one item, quantity one. Monthly/yearly intervals are shown to the customer; the quoted subtotal excludes checkout-calculated taxes.

Issuing fixes the title, customer, scope, line prices, interval and expiry for that revision. If catalog details change, create a revision using the current catalog and issue it. Only the newest revision can be issued; issuing it supersedes previous issued versions. A series with an accepted order cannot be revised into another order automatically. New unrelated purchases require an explicit new quote series.

## Record customer approval

Share the **private customer link** manually when ready. The link is signed, expires at the end of the stated date in the application time zone and is bound to the issuing application's host and the quote's saved website identity. This keeps links on the database/instance that issued them, including when an agency manages a client website from a different hostname. Anyone holding it can read/acknowledge that revision; it is not email identity verification or a separate signature workflow.

Alternatively, staff can record approval received elsewhere, with the customer name, approval reference and explicit confirmation that the customer approved this exact revision. The quote records the approval channel, name, time and staff actor when applicable.

Acceptance rechecks the revision, expiry and catalog. A lost deal must be reopened deliberately before acceptance. The operation creates one pending order through **LightekCommerce::OrderPlacement**, snapshots the existing product/billing/installation terms, links the quote to it and marks the deal won at the agreed catalog subtotal. Repeating acceptance returns the same order. An acceptance failure rolls the sales/order changes back; it never charges the customer.

## Payment and delivery

The customer chooses **Review & pay securely** to use the existing Stripe/network checkout. Checkout uses the linked order, never a customer-supplied order ID. The customer reviews the checkout total and taxes before paying. The existing processor idempotency keys and verified webhook settlement remain the payment authority.

Returning from checkout is not proof of payment. The quote's order section reads the actual order's paid timestamp/status, fulfillment timestamp/reference and managed-installation provisioning timestamp. Existing fulfillment and paid-instance provisioning services own delivery; quote acceptance does not mark anything paid or fulfilled.

Staff follow **Manage payment and delivery in Commerce** for order/refund/fulfillment/recovery operations. Existing orders and subscriptions retain their saved financial and installation snapshots. This connection does not create a second ledger, invent Bank invoice APIs, change settlement rules or bypass provider setup.

An expired/canceled pending order is not silently replaced by accepting again. Review the existing order/checkout in Commerce before preparing a new offer. A paid order is never duplicated to retry delivery.

## Operator trail

Each quote has a website, deal, series/revision, issuer activity, acceptance record and linked order. Follow those IDs to the existing checkout/payment reference and delivery receipt. Structured diagnostic events `lightek.sales.quote_issued` and `lightek.sales.quote_accepted` include quote/site/order IDs and the approval channel, without logging the private link or customer details.

The deal keeps its activity history and quote/order links; the buyer sees only customer-facing quote terms and the linked order's payment/delivery state. Expired/superseded links cannot accept a different revision. Signed-link possession permits customer review; no customer messages are sent by this implementation.

## Verification

The lifecycle/quote acceptance suite runs real CRM and Commerce models and the real OrderPlacement transaction. Processor checkout, payout-sharing dependencies and private engine authentication are fixture boundaries in that suite. The existing Commerce suite separately exercises verified settlement, inventory, refunds and payment safety at its provider boundaries. Live processor webhooks, managed-installation provisioning, buyer-facing TLS/domains and native host MFA require deployed acceptance.

```sh
SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/lifecycle_quote_checks.rb
SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs
ruby test/standalone/commerce_order_cleanup_test.rb
```
