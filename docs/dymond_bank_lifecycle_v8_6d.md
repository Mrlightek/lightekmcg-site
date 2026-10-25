# Dymond Bank — unified financial lifecycle (V8.6D)

Dymond Bank owns the money lifecycle for Lightek. Subscriptions, checkout, invoices, payment settlement, balances, transfers, payouts, and Susu are Bank services, not separate financial backends. Dymond Dash is the administrative and customer control plane; Gatekeeper fulfills paid, authorized service obligations.

## Contract boundary

1. Bank catalog/order/checkout produces a payment request and immutable identifiers.
2. A verified processor event is idempotently reconciled by Bank into its ledger and invoice or subscription lifecycle.
3. Bank publishes a stable paid/active service entitlement; Gatekeeper provisions from that entitlement once, with receipts.
4. Refund, dispute, missed renewal, cancellation, and reactivation trigger appropriate Bank lifecycle states and provisioning reviews.
5. Every money-changing operation is auditable, double-entry where applicable, and idempotent. Internal ledger balances never substitute for bank deposits or regulated custody accounts.
6. Susu participates in Bank identity, accounts, accounting, payment authorization, and reconciliation; its group rules remain a product service.

## V8.6D scope

Read-only subscription registry for super_admin, plus local Bank engine and provisioning contract report. No write routes, migrations, charges, transfers, or ledger mutations. Next slice will bind create/cancel/change/renew operations to the verified Bank service methods and test webhooks, idempotency, accounting entries, and provisioning.
