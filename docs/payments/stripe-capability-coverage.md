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
