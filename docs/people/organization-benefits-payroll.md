# People, corporate structure, benefits and payroll

Open **People & Access** in the dashboard sidebar. Settings → People & access also links to the directory and payroll workspace. Every screen and action is scoped to the selected employer account.

## Build the organization

1. The enterprise starter adds 26 default departments/subdepartments on first use, including IT, Accounting, Payroll, Shipping, Receiving and Legal & Compliance. Add or adapt departments for the business; existing custom and archived departments are preserved. Department codes provide stable cost-center identifiers.
2. Add existing Lightek accounts as team members. Select employee, freelancer or agency, a title, department, job level and start/end dates.
3. Set **Reports to**. Managers can supervise managers, team leads and individual contributors; team leads supervise individual contributors. Reporting relationships can cross departments within the employer. Circular and cross-employer reporting are rejected.
4. Assign access independently. Only the employer owner can grant people administration or payroll responsibility. Managers and leads can view their reporting chains; that title does not grant compensation access. An HR administrator cannot promote themselves into payroll.

This is Lightek's business directory. The legacy top-level `Department` scaffold belongs to `SystemJob`; business departments use `LightekPeople::Department` so HR data does not leak through that legacy generic CRUD surface. Employment memberships do not change `User.role`, reseller `agency_id`, or existing server privileges. Enterprise identity adds OIDC sign-in, remote joining to existing AD/Samba AD domains and explicit Gatekeeper resource permissions through the separate IT Directory & Access workspace. Those controls consume explicit permissions rather than treating a management title as infrastructure authority. See [enterprise identity](../enterprise-directory-and-accounting.md) and [first sign-in/MFA](../security/sign-in-and-mfa.md).

## Employer boundaries and delegation

A worker can belong to several employers. Agencies and client businesses use the same model, including nested reseller clients. Reseller ownership alone does not reveal another employer's payroll: the employer must explicitly add and authorize the delegate. Users with business roles can manage their own employer account. Payroll roles are:

| Responsibility | Prepare statements and benefit plans | Read register | Approve / release |
| --- | --- | --- | --- |
| None | No | No | No |
| Preparer | Yes | Yes | No |
| Approver | No | Yes | Yes |
| Administrator / employer owner | Yes | Yes | Yes |

A different authorized person must approve a run: its creator and anyone who prepared a statement cannot approve their own work. The employer owner should grant an accountant or another authorized staff member the appropriate role before the first run.

## Benefits

Payroll preparers create USD plans with employee and employer contributions **per prepared pay statement**. Employee memberships elect published plans under My employment. Ending enrollment is effective that date (exclusive end); re-enrollment keeps the old election record. Existing elections continue if a plan closes to new enrollment. Pre-tax/post-tax treatment and contribution amounts are snapshotted on the pay statement.

These records do not purchase insurance, enroll with a carrier, determine statutory eligibility, apply annual contribution caps, or automatically calculate a tax exclusion. A payroll reviewer must supply the correct tax result after considering these benefits. Employer contributions and withheld amounts remain separate liabilities; sending net pay does not remit them.

## Prepare and release payroll

1. An employer owner opens Payroll → Configure employer payout sender. Enable Stripe Global Payouts / Treasury in that employer's Stripe account, fund its FinancialAccount, and provide its FinancialAccount ID and restricted API key. Live unrestricted `sk_live` keys are rejected. Sandbox keys are supported.
2. Grant the key Stripe's documented recipient configuration, financial-account read, payout-method, outbound-payment and payout-intent permissions. The sender ID is verified against the key, bound uniquely to this employer, and credentials are encrypted in Vault with a workforce-only consumer/purpose. There is no environment-file setup or fallback to platform merchant proceeds. Rotate keys through the same form; an employer with recipients cannot switch to a different financial account.
3. Workers open My employment → Set up / update bank details. Lightek creates an employer-scoped Stripe recipient and redirects the authenticated worker to Stripe's single-use hosted form. Routing numbers and bank account numbers are entered directly at Stripe. Returning to Lightek refreshes ACH eligibility; a return redirect is not evidence of completion. An expired link returns to a signed-in screen with a fresh setup button.
4. A preparer creates a pay period and pay date, then adds each worker's reviewed gross pay, employee taxes, other deductions, employer taxes and calculation/review reference. Benefits are taken from elections on the pay date. Saving the same worker replaces their draft statement. Gross-to-net uses integer cents; negative net pay and duplicate runs for the same period/pay date are rejected. USD is the initial supported currency.
5. A different authorized approver reviews the register and approves. Amounts, identities, benefit snapshots, period and sender reference then become immutable. Corrections require canceling a run before any payout attempt and preparing a replacement. CSV export identifies monetary columns as cents and neutralizes spreadsheet formulas.
6. On or after the pay date, an approver prepares each net payout. Stripe PayoutIntents use manual confirmation. Review the provider fee quote, acknowledge it and release. If fees changed, review again. Bank funds come from that employer's FinancialAccount; Stripe rejects insufficient funds. Approval alone does not move money, and this release does not automatically schedule future releases.
7. Refresh status to reconcile processing, posted, failed or returned attempts. **Posted** means funds left the sender, not guaranteed receipt by the employee's bank. Failures and returns never create a replacement payment automatically. Provider actions other than ordinary manual confirmation require resolving them in Stripe and refreshing here. There is no webhook/scheduled reconciliation in this release.

Stable per-statement idempotency keys and row locks prevent double release from repeated clicks or concurrent requests. The initial attempt timestamp is committed before provider IO. An unresolved creation attempt older than 23 hours fails closed before the provider's idempotency window can expire; operators must reconcile it with Stripe rather than create a replacement. Keep that statement/run in place and use the persisted statement ID in the provider description/idempotency key to investigate. This release has no manual override that can claim a payment succeeded.

## Accounting scope

The register records gross pay, employee taxes, other deductions, benefit withholding, net pay, employer taxes and employer benefit costs. Workers see only their own approved statements. Former members retain access to their own historical statements and bank setup for final pay, but lose team visibility and delegated HR/payroll authority. Set an end date when offboarding so a reviewer can prepare owed wages for a period that overlaps employment. Payroll audit events identify the employer, actor, action and affected record without storing bank details or provider credentials.

Tax amounts are explicitly reviewed inputs, not an automatic jurisdictional tax engine. This release does not submit W-2/1099 forms, file payroll returns, deposit employment taxes, remit retirement/insurance contributions or create statutory accounting journals. The accounting firm can review/export the register while those provider integrations are added. Worker type records do not determine legal employee/contractor classification.

## Validation

`ruby test/standalone/people_http_checks.rb` runs public Rails model/service and real controller/template tests without private engines or live provider credentials. Set `PEOPLE_DATABASE_URL` to an empty PostgreSQL test database to include the simultaneous payout-preparation test. The GitHub workflow runs PostgreSQL and verifies authorization, self-service, cross-employer rejection, reporting cycles, frozen statements, independent approvals, fee changes, timeouts, old attempts, hosted-onboarding contracts and CSRF.

Provider references: https://docs.stripe.com/global-payouts/recipient-creation · https://docs.stripe.com/global-payouts/send-money · https://docs.stripe.com/global-payouts/manage-payouts · https://www.irs.gov/businesses/small-businesses-self-employed/understanding-employment-taxes
