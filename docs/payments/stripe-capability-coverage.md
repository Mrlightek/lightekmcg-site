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

Local and Lightek VPS storefront carts and accepted local quotes use embedded checkout by default when the processing platform’s publishable key is available. The provider's browser component collects payment details inside the storefront and can request payment-method authentication when required. The signed billing webhook remains authoritative for settlement and fulfillment. Existing hosted sessions retain their original payment presentation. Separate checkout entry points such as dedicated package signup continue to use their existing checkout.

The merchant payout calculation separates the configured processor reserve, Lightek platform fee, infrastructure reserve, and eligible upstream allocation. `LIGHTEK_COMMERCE_PLATFORM_FEE_BPS` defaults to zero when unset. Verify the deployed fee schedule, real processor costs, refund and dispute treatment, and signed settlement receipts before using these amounts in projections. Test paid and refunded orders for one agency and one agency-client merchant, including independent bank setup, order attribution, transfer or release, and bank arrival.

A platform administrator with a verified session can open **Commerce → Merchant payouts → Check Stripe access**. The checks use the installed Vault-bound credentials and return read access and mode for known resources. They perform no provider writes and disclose no provider records. Use these checks for the initial account inventory and run a controlled sandbox workflow to verify write and event permissions for each product.

## Buyer-inclusive pricing and merchant reconciliation

The intended pricing model preserves the merchant's listed merchandise price. The Lightek network fee and estimated processor recovery are included in the full buyer price shown up front. The pricing preview in **Commerce → Merchant payouts → Order ledger** applies the estimate to the full pretax buyer amount, including the fees themselves. Tax, shipping, agency contracts and actual processor cost are separate. The network fee is the intended markup. Processor recovery covers the cost of the payment and is reconciled against Stripe's recorded fee. The variance belongs in Lightek's reconciliation while preserving the merchant principal under this pricing model.

The preview starts with a $2 Lightek network fee per transaction. It grosses up the pretax buyer amount for estimated processing and rounds up to the next multiple of $2, keeping an already even total. Recalculate estimated processing on that rounded buyer total. The remaining amount above the merchant price and the estimate is the Lightek network fee. At a $100 merchant price and an assumed 3% plus $0.30 processing schedule, the $106 buyer total leaves $3.48 in estimated processing and $2.52 in network revenue.

The order ledger compares the original Stripe charge's recorded fee, processor net and balance status with the order, refunds, upstream allocations and merchant transfer. For buyer-fee orders it also shows the buyer charge less actual processor fees and any merchant transfer reversal. The bank deposit workflow can link provider-matched connected-account entries to orders on the payment ledger. VPS storefronts open deposit and dispute details in the central Lightek Dashboard, where owner sign-in and recent MFA still apply.

### Collect buyer fees on eligible storefronts

Apply the migration and set `LIGHTEK_COMMERCE_BUYER_FEE_HOSTS` to approved storefront hosts and `LIGHTEK_COMMERCE_BUYER_FEE_TAX_CODE` to the Stripe Tax product code approved for the checkout fee. An empty host list keeps the feature off. Review all price placements on each pilot storefront before enabling it. The pilot uses one unit of one one-time digital product or service without a variant, upstream share, hosting package, or shipping. For a VPS storefront, approve its storefront host on the VPS and the registered installation host on central Lightek. Both sides use the same buyer pricing configuration. The central service independently recalculates the buyer total before creating the payment and records the full merchant principal. Other sales channels and subscription renewals are outside this rollout.

The catalog and cart show the all-in pretax price. A signed cart quote expires after 15 minutes. The order freezes its agreed prices and processor estimate, validates payment totals against Stripe's signed event, and preserves the merchandise principal for merchant release. The receipt itemizes the checkout fee. Tax is calculated by the existing Stripe Tax integration and can change the final total and actual processing cost. The difference between the fee estimate and Stripe's actual charge belongs in Lightek reconciliation.

Refund these orders inside Lightek. A full refund includes the checkout fee. If the merchant principal was already transferred, the refund queues a reversal with a stable provider key. An older uncertain transfer or reversal requires reconciliation before any replacement money movement. The ledger distinguishes a merchant release, a pending reversal and a recorded reversal.

Validate all-in displays and the fee tax treatment for the pilot market. Test one fee-bearing order from published price through signed payment, merchant transfer, and full refund before enabling live mode. This is a tender-neutral buyer price. Card-only surcharge treatment has separate requirements.


### Merchant bank deposits and disputes

From **Commerce → Merchant payouts → Bank deposits**, a local store owner can view deposit status and open the provider's transaction list for reconciled automatic deposits. Download the current transaction page as CSV. Lightek links an entry to a local order only if its provider transfer matches that order's saved merchant transfer. Unmatched adjustments remain visible as provider entries. Deposit dates and statuses come from the provider.

From a paid storefront order, **View payment disputes** shows the provider's status and response deadline. An authorized owner can review and submit a text response for a matching open dispute. File evidence, store-wide dispute alerts, funds recovery automation, and live agency/client bank arrival acceptance remain open.
