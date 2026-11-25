# IT Services business operations

Batch C adds Managed IT subscriptions and IT appointment billing to the existing Commerce and Dymond Bank flow. It uses the Nevaeh case and technician completion records from Batch B (#426). Deploy both batches before enabling sales. The billing page keeps enrollment unavailable until the Batch B request model and payment clearance are installed.

## Managed IT subscriptions

1. In Commerce, create a dedicated service product with a monthly or annual price. Keep it unpublished until it has been linked.
2. In Reservations, create a service resource for appointments included with the plan. Use the same website as the product. Leave the resource’s Commerce product blank.
3. In Business → More business tools → **IT Services finance**, link the product and resource. Publish them through Commerce and Reservations.
4. Customers select the plan in the shop or **IT Services billing**. Checkout uses the existing Dymond Bank integration. Paid invoices, renewal status and cancellation are visible to the signed-in account that bought the plan.
5. From **IT Services billing**, customers book an included appointment and link it to their IT support request. Gatekeeper checks the paid term both at booking and at Nevaeh dispatch. The entire appointment must fit in a verified term. Canceling renewal preserves the paid term.
6. For one-time appointments, register a priced Reservations resource in **IT Services finance**. The customer’s confirmation in the IT case triggers Commerce fulfillment. Orders requiring financial review remain visible in Commerce.

A coverage period comes from a verified initial or recurring invoice containing the expected subscription line and full payment. Failed bills, prorations, credits and refunded payments cannot open a covered appointment. This release sells through the local Commerce storefront. Federated reservation peers use their existing settlement path for one-time bookings.

## Technician payouts

A payroll preparer with fresh MFA selects customer-confirmed cases for one technician on the servicing website. The technician must be registered in People & Payroll for the site’s owner. The preparer enters the reviewed gross amount per case and the pay statement’s reviewed deductions. A separate payroll approver approves the run. Release and provider reconciliation use the existing employer-funded Dymond Bank workforce payout flow. Merchant earnings and agency revenue shares continue through Commerce.

The finance screen links each case to its payroll statement and displays the provider-backed settlement state. A repeated submission reuses the prepared statement. A canceled draft can be restaged with the same reviewed technician and gross amounts. A statement with a provider attempt stays on its existing reconciliation path.

## Release acceptance

Run the PostgreSQL acceptance workflow on the candidate revision. The same test runs against the Batch B services once they are present in the checkout. To require the cross-batch path in an isolated candidate, use the following command with a dedicated test database.

```sh
IT_SERVICES_REQUIRE_BATCH_B=1 \
RESERVATIONS_DATABASE_URL=postgres://localhost/it_services_test \
ruby test/standalone/it_service_business_checks.rb
```

After the standard migration and worker restart, run the release probe on the deployed revision.

```sh
bin/rails runner script/lightek/it_service_release_check.rb
```

The probe checks installed tables, route registration, the signed webhook integration and the settlement queue consumer. Release acceptance also requires a configured payment and workforce environment. Confirm that a real customer payment produces a verified invoice and permits booking, a customer-confirmed case settles once, a renewal or failed payment updates coverage, and the approved technician payout reconciles to its provider receipt. Record the order, invoice, case and payout receipt IDs in the release record.
