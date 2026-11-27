# Stripe capability coverage in Lightek

Dymond Bank owns provider access. Lightek screens and workers should call typed operations that enforce the account, purpose, permitted actor, and provider receipt. Keep credentials in Vault and use the relevant KYC, review and release controls.

| Stripe capability | Existing Lightek integration | Evidence to check on the installed account |
| --- | --- | --- |
| Checkout, recurring billing, payment events and refunds | Commerce checkout, subscriptions, signed Stripe event routing and refund workflow | Checkout and credentials mode, supported payment methods, signed event delivery and settlement |
| Connect onboarding and merchant transfers | Dymond Bank payout accounts and Commerce merchant payouts | Platform access, connected account requirements and eligible transfer |
| Global Payouts sender, recipients and ACH | People & Access and Sales & CRM referral payouts | Vault sender binding, provider permissions, funded financial account and active recipient ACH capability |
| Creator, broadcast and Susu disbursements | Dymond Bank and the respective payout workflows | Capability and funding for each workflow's account and recipient |

The **Check payout connection** action in Sales & CRM verifies read access to the configured financial account. It does not establish recipient eligibility, available balance, write permissions, or access to other Stripe products. The partner's setup page checks ACH readiness on the linked recipient.

Track additional operations per provider account, environment and Vault credential. For each operation, record the Stripe product and API version, required key permissions and account eligibility, Lightek entry point, read/write scope, and sandbox/provider acceptance evidence. Classify permissions and enabled provider products as unknown until verified with that installation's authorized connection. The Stripe API reference alone establishes the available interface, not this account's entitlements.

## Merchant commerce path

An agency or client that owns a store can open **Commerce → Merchant payouts** for its own account, verify its payout connection, and release eligible fulfilled orders manually or on a schedule. A delegated manager cannot use this workflow to edit another person's bank details or release their orders. Embedded Connect onboarding and account management depend on the installed account and matching publishable key. Some browsers, requirements, and account configurations use the existing secure hosted fallback. Federated installations synchronize earnings with the central Lightek platform.

Local storefront carts can opt into Lightek-hosted checkout with `LIGHTEK_COMMERCE_EMBEDDED_CHECKOUT=true` and a same-platform publishable key in the established credential configuration. The provider's browser component collects payment details inside the storefront and can request payment-method authentication when required. The signed billing webhook remains authoritative for settlement and fulfillment. Federated carts and separate checkout entry points, including standalone quote checkout and dedicated package signup, use their existing payment presentation.

The merchant payout calculation separates the configured processor reserve, Lightek platform fee, infrastructure reserve, and eligible upstream allocation. `LIGHTEK_COMMERCE_PLATFORM_FEE_BPS` defaults to zero when unset. Verify the deployed fee schedule, real processor costs, refund and dispute treatment, and signed settlement receipts before using these amounts in projections. Test paid and refunded orders for one agency and one agency-client merchant, including independent bank setup, order attribution, transfer or release, and bank arrival.

A platform administrator with a verified session can open **Commerce → Merchant payouts → Check Stripe access**. The checks use the installed Vault-bound credentials and return read access and mode for known resources. They perform no provider writes and disclose no provider records. Use these checks for the initial account inventory and run a controlled sandbox workflow to verify write and event permissions for each product.
