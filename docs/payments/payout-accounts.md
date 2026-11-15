# Payout accounts

## Customer workflow

Open **Settings → Your account → Payout account**, or **Commerce → Merchant payouts → Add or manage payout account**. Sign in as the actual payout owner and verify MFA. Payout account setup is available to signed-in individuals, agency owners and their clients independently of the optional Susu application. An agency's delegated management session cannot change another person's bank destination.

Choose **Set up payouts** or **Continue payout setup** to enter business/individual details, identity verification and the bank destination. **Manage account & bank details** opens the account-management component. These financial fields are provider-controlled embedded fields; Lightek does not receive the full bank numbers, tax identifiers or identity documents through its Rails forms. Required financial-service terms and authentication are handled inside the verification workflow. Lightek's surrounding UI uses provider-neutral payout language; legally or technically required provider screens may identify the provider.

If this browser cannot display the embedded fields, use **Secure fields not loading? → Open secure verification**. This creates a short-lived hosted setup link for the same signed-in owner. JavaScript is not required to submit that fallback form, although the verification provider's page may require it. Existing links retain their account identity rather than silently creating another destination.

Use **Refresh status** after verification. Ready means the latest account lookup confirmed submitted details, payouts enabled and an active transfers capability. Information still under review is not presented as ready. Failures clear the cached payout-enabled flag and show a display-safe explanation. Ordinary dashboard cards describe a linked account rather than claiming a fresh verification that has not happened.

Payout account setup does not release funds. Existing paid-order, fulfillment, refund, reserve, revenue-sharing and reconciliation checks continue to govern earnings release. Existing weekly/biweekly release preferences remain separate from bank arrival.

## Connected installations and downstream clients

A connected installation resolves the signed-in person's account chain with the platform before opening central payout setup. Its current merchant summary and payout schedule use that merchant's chain, not the installation owner's identity. The platform validates every account mapping against the peer's reseller branch. Destination/account IDs in client parameters are not accepted.

The person then signs in to their own central Lightek account and verifies MFA before editing bank information. A first-time mirrored identity uses the existing first-password invitation/reset workflow. Local credentials and the central account can have different passwords. Peer credentials and agency roles never produce an embedded financial session for someone else's bank account. The legacy federation connect operation now returns the central authenticated payout workspace, not a bank-editing credential or hosted financial link.

## Operator configuration

Only the platform operator configures payment-provider keys. Merchants and their customers do not supply API keys to set up their personal payout account.

The backend uses `DymondBank::StripeCredentials.secret_key`. The browser initialization uses `DymondBank::StripeCredentials.publishable_key` when available, otherwise `LIGHTEK_PAYOUT_PUBLISHABLE_KEY` or `STRIPE_PUBLISHABLE_KEY`. These must belong to the same platform and use matching test/live modes. The public key is intentionally publishable; the private key never appears in the session response or page markup. New accounts retain the existing US Express configuration and request transfers. International country coverage requires a separate supported-country policy rather than assuming every country is eligible.

Stripe Connect and the required connected-account/session permissions must be enabled on the configured platform account. Successful local mocks cannot establish that the production platform has those permissions. Do not change account liability/requirements collection settings merely to suppress required provider authentication.

Production payout pages require HTTPS. Account-session responses are owner-scoped, CSRF-protected, private/no-store, direct-MFA protected and rate limited. Only account onboarding and account management are enabled; refunds, captures and payout initiation are not granted through embedded sessions. Session credentials stay in memory, are renewed through the authorized backend and are never placed in URLs or browser storage. Sign-out invokes embedded-session logout when the payout module remains loaded.

If you impose CSP headers upstream, allow the provider's documented Connect.js/frame origins. The provider also documents popup/header requirements and supported browser versions. Do not strip required verification text or terms from provider components. Reference: [Connect embedded components](https://docs.stripe.com/connect/get-started-connect-embedded-components?platform=web) and [account management](https://docs.stripe.com/connect/supported-embedded-components/account-management).

## Inaccessible saved connection

An access/unknown-account error means the configured platform key cannot access that saved account reference. First restore the correct platform credentials and mode. A code deployment cannot grant one platform access to another platform's account.

Only when the provider reports a missing/invalid account reference does the UI offer **Repair an unavailable connection**. The owner must explicitly acknowledge that a new connection does not recover an old balance. The server rechecks the failure, creates a new connection with a distinct idempotency key, and records the prior account, replacement, platform and mode in `lightek_payout_connection_changes`. It never deletes the old remote account, migrates balances, changes paid-order receipts or marks the replacement ready. Complete verification on the replacement before receiving new earnings. Invalid credentials, transient outages and accessible accounts do not allow this replacement path.

Apply migration `20261115110000` before using connection replacement. Preserve the audit records for reconciliation.

## Verification

```sh
ruby test/standalone/payout_accounts_checks.rb --name /test_payout_/
ruby test/standalone/payout_network_checks.rb
node test/javascript/payout_accounts_test.cjs
```

These checks exercise real account/session/MFA/CSRF handling and database writes, with provider calls replaced at their boundary. They cover agency/client identity separation, fresh status, inaccessible references, explicit replacement, audit retention, request key isolation, hosted-link allowlisting, ephemeral frontend credentials, renewal and error redaction. The live provider flow still needs a test-mode acceptance run with the platform's own keys, followed by its production activation checks. No real banking or identity information belongs in the tests.
