# Enterprise identity, bookkeeping and source monitoring

This release extends the existing Rails Dashboard, Gatekeeper fleet, Vault and Dymond Bank workspace. It does not move customers to a new stack or create a second billing system.

## Start in Dashboard

1. Open People & access as the employer owner. The first visit adds missing enterprise departments, including IT, Accounting, Payroll, Legal & Compliance, Shipping and Receiving. Existing custom departments and archived departments remain intact. Managers, team leads, reporting lines and individual contributors remain separate from permissions.
2. Set up an authenticator under My sign-in security. Save the recovery codes once, privately. Password authentication gives only enrollment access when company policy requires MFA; an enabled authenticator requires verification before a full session is created. Corporate policy defaults to MFA required. Privileged platform staff, IT administration and financial actions retain MFA requirements even when a company relaxes its general policy.
3. The owner appoints IT administrators through the employee's IT administrator checkbox. This is an explicit employer-scoped permission, not a privilege inherited from the IT department name or management title. HR cannot appoint IT administrators. IT does not thereby receive HR, payroll, banking or accounting authority.
4. IT opens Directory & access to manage directory principals, security-bearing department assignments, SSO, realm joining and resource grants. Changes require a current password and a fresh MFA session. HR may maintain ordinary organizational details but cannot move someone into a department with infrastructure grants or extend a privileged membership to regain access. The owner controls restoration of privileged employment and department activation.
5. Assign accounting bookkeeper, reviewer or administrator and legal/compliance reviewer or administrator independently. Payroll preparation and approval remain separate. An employee's bank setup uses the existing processor-hosted onboarding; this release does not ask users to upload raw routing/account numbers into new bookkeeping fields.

## Sign-in and recovery

For the exact first-login screens, manual authenticator setup, recovery and troubleshooting, see [First sign-in, MFA and recovery](security/sign-in-and-mfa.md).

Authenticator codes follow RFC 6238 (six digits, 30 seconds), reject replay, and use row locking. Ten one-time recovery codes are stored as hashes. Authenticator secrets and pending enrollment are Vault-envelope encrypted. Enrollment expires after ten minutes; a verified MFA session is fresh for twelve hours. Disabling a factor requires a current password, fresh MFA, and company policy permitting it. Other sessions are invalidated when security changes.

OIDC supports authorization code plus PKCE S256, exact configured issuer/audience, RS256 signing keys, nonce, browser-bound state and five-minute single-use attempts. Configure public HTTPS endpoints and register the callback shown by Dashboard. Client secrets go directly to Vault with the organization-specific consumer policy. Users first link their immutable provider subject from an authenticated local account protected by an independent authenticator; email matching never links accounts automatically. An organization-controlled IdP alone cannot authenticate as another local account without that account's independent factor. Disabling the connection or employment invalidates its SSO sessions. Local login remains available.

Recovery codes are the implemented self-service recovery path. No unauthenticated factor reset, SMS fallback or automatic support override is introduced.

## Directory joining and authorization

The Linux integration joins a remote Ubuntu node to an **existing** Active Directory or Samba AD domain using realmd, SSSD and adcli. It does not create a domain controller, implement an LDAP server or replace Entra ID. Configure domain DNS, network reachability and clock synchronization first. Enter delegated join credentials in Dashboard; Vault checks them out only for a node join. No extra environment secret is required.

Only employer-owned remote nodes are eligible. Auto-join is opt-in. Explicit per-person and direct-department grants distinguish read, manage and domain login. Domain login grants do not grant sudo. Active membership dates, department activation and current resource ownership are checked. Delegated resource access does not expand account ownership, billing authority, new provisioning spend or client-owner management sessions.

Gatekeeper transmits join secrets over its existing secure transport through stdin. The root helper rejects unmanaged realms, serializes changes, writes root-only ownership markers, disables offline credential caching and applies a deny-first allowlist. Monotonic revisions prevent delayed jobs from restoring an older grant after revocation. Failures are surfaced as needs-review, without storing secret-bearing exception text. Membership changes queue reconciliation; a five-minute sweep and date-boundary timers handle scheduled changes. Server changes are asynchronous and do not terminate already established SSH sessions. Application authorization is checked on subsequent requests.

## Native bookkeeping workflow

Open Books & accounting from Dymond Bank or Dashboard. Select the employer and book. Existing commerce/bookkeeping feature eligibility and subscriptions are reused.

1. Create a USD bank account with a reviewed opening date and opening balance.
2. Upload or paste a statement. CSV, TSV and TXT support explicit column mapping, ISO / month-day-year / day-month-year dates, signed, debit-positive or separate debit/credit amounts. OFX/QFX supports bounded XML and common SGML statement transactions. Review the preview before committing.
3. Commit through the worker. Exact source reimports and bank FITID duplicates are idempotent. Ambiguous CSV matches need explicit acceptance; conflicting FITID values fail. Imports are transactional and recheck the actor's current employer permissions.
4. Classify transactions with categories and literal keyword rules; bulk changes are capped and audited. Search and filter within the selected book. Imported amounts and source identity cannot be silently edited.
5. Reconcile consecutive periods against the previous ending balance. Mark cleared entries, review outstanding checks/deposits and both live difference proofs, then finalize with reviewer authority. The server recomputes proofs when saving. Closed periods reject new entries; only the latest final period can reopen, preserving its original proof as superseded.
6. Review cash-basis monthly/annual profit and loss and Schedule C category workpapers. Transfers and equity are excluded from profit. Deductibility is calculated per category, including aggregate penny rounding. This is not double-entry accrual accounting, a general journal, an inventory engine or a completed tax return.

Financial source data, amounts, descriptions, workbook cells, formulas and saved report outputs are encrypted with existing Vault cryptography and record/book context binding. Tenant IDs, dates, labels, status and indexes remain queryable metadata. Protect database backups **and** the existing Vault master key according to the platform backup/restore procedure; ciphertext alone cannot restore the financial records. Use the existing HTTPS deployment and backup system. This change does not install a second backup service or certify an infrastructure encryption configuration.

Imports are bookkeeping evidence. They never credit Dymond Bank spendable balances or trigger money movement. CSV exports neutralize spreadsheet formula injection. Audit records identify the actor and action with proof digests; they are not claimed as externally notarized or tamper-proof.

## Spreadsheet to native systems

The Workbooks tab accepts XLSX and CSV/TSV/TXT as structured input. XLSX parsing reads the archive without extraction, preserves worksheets/cells/formulas, handles supported Excel dates, and does not trust cached formula results. Limits: 5 MB upload, 30 MB expanded archive, 400 entries and 50,000 populated cells. Macros, embedded objects, external relationships and XML entities are rejected.

The bounded native formula subset includes arithmetic, comparisons, concatenation, local and worksheet references, ranges, SUM, MIN, MAX, COUNT, AVERAGE, IF, IFERROR, ROUND, ABS, SUMIF and COUNTIF. Supported calculations use decimal arithmetic. Unsupported formulas, shared/array formulas, ambiguous types and wildcard criteria require review; they are not replaced by cached results. This is a supported-subset converter, not full Excel or Google Sheets parity. Input changes recalculate native formulas; formula cells cannot be overwritten through the input editor.

Conversion targets:

| Target | Recognized columns | Result |
| --- | --- | --- |
| Transactions | User-mapped date, description, amount/debit/credit and optional reference | Statement preview; explicit review and commit still required |
| Categories | Name, Kind, Deductible Percent, optional Schedule C | Native categories, conflict review and idempotent conversion manifest |
| Keyword rules | Keyword, Category, optional Priority | Native categorization rules referencing reviewed categories |

Uploading the accounting client's real workbook and HTML prototype can reuse the supported-format pipelines when provided. No client source or workbook was supplied or migrated in this release.

## Taxes, scheduled work and external activation

The versioned `irs-1040es-2026-v1` estimator implements a reviewed-input 2026 ordinary-income sole-proprietor projection: progressive federal brackets, base standard deductions, Schedule SE factors and wage cap, Additional Medicare threshold, half-SE deduction, safe-harbor tests, withholding and manually recorded payments. Monthly/annual Schedule C workpapers do not themselves establish a federal filing obligation or produce an IRS-approved submission. Unsupported years fail closed.

Users must review filing status, wages, adjustments, deductions, credits, other taxes and prior-year inputs. QBI, capital-gains rates, AMT, state taxes, multiple self-employed spouses and annualized-income installment methods are not automatically calculated. Tax reserves are distinct from actual tax payments.

Daily/weekly workers refresh encrypted reporting outputs and reviewed estimates. They recheck current actor permissions and factor enrollment. Scheduled payroll work requires an already-approved run and an authorized actor, prepares existing payout quotes only, and does not automatically approve/release funds. Existing payout approval and reconciliation remain authoritative.

| Integration | Implemented | Activation / remaining work |
| --- | --- | --- |
| OIDC | Authorization-code/PKCE connector and subject linking | Enroll application at the real IdP, configure exact endpoints/Vault secret, verify live sign-in |
| AD/Samba AD | Remote join and managed allowlists | Existing domain/DNS and delegated credentials; test a real node join/revocation |
| IRS estimates | Local, source-versioned 2026 calculations and workers | Review inputs and yearly published updates |
| IRS e-filing | **No transmission adapter in this release** | Product-specific enrollment, secure SOR schema/WSDL access, adapter implementation and ATS testing/certification; entering a credential does not enable filing |
| Open States | API v3 legislative search | Vault API key and live provider verification |
| NY Open Legislation | Official API v3 law search | Vault API key and live provider verification |

IRS does not provide a general public calculation API that replaces the local bookkeeping/tax engine. MeF transmission and IRIS information-return APIs are distinct products with enrollment and testing requirements. Their future credentials belong in Vault; this release does not file returns, enroll Lightek, transmit tax records or remit taxes.

## Legal and compliance evidence

Select an operating state and explicit search terms under Legal & compliance. Open States monitors legislative activity for supported US state/DC jurisdictions. Bills are not labeled enacted law. New York additionally supports the official law search endpoint. Daily workers store bounded source evidence with links, timestamps, coverage and needs-review status; query scope is the first 20 results, not an exhaustive legal inventory. Failed refreshes mark evidence stale. Revoked permissions stop the monitor. Owners store API keys in Vault; compliance administrators configure monitors and reviewers inspect evidence.

This release does not infer a universal legal obligation set or certify that an employer complies with all state law. Add a jurisdiction/provider adapter only after checking its published contract and coverage.

## Validation and references

`test/standalone/enterprise_http_checks.rb` runs native controller/ERB and service checks against public Rails dependencies, including actual password/MFA cookie flow, restricted enrollment, two-employer isolation, HR/IT separation, live revocation, imports, reconciliation, encrypted outputs, formula/security cases and source contracts. The dedicated enterprise acceptance workflow runs on PostgreSQL 16 with Rails 8.0.5. `test/operations/directory_membership_test.py` exercises the root helper through fake OS commands without joining a real domain. Real IdP, AD and API provider acceptance still requires configured test accounts. Full private-engine application boot and visual browser review are not covered by this harness.

Primary references:
- https://openid.net/specs/openid-connect-core-1_0.html
- https://ubuntu.com/server/docs/how-to/sssd/with-active-directory/
- https://www.irs.gov/pub/irs-pdf/f1040es.pdf
- https://www.irs.gov/e-file-providers/modernized-e-file-mef-schemas-and-business-rules
- https://www.irs.gov/e-file-providers/assurance-testing-system-ats
- https://docs.openstates.org/api-v3/
- https://v3.openstates.org/openapi.json
- https://legislation.nysenate.gov/static/docs/html/
- https://support.microsoft.com/en-us/excel/calculation-operators-and-precedence-in-excel

## Agency-to-client MFA

Lightek Connect now verifies the connected agency's browser at the central origin and binds the handoff to that direct MFA session. Local and remote delegated requests revalidate the grant and revocation state before opening sensitive workspaces. The client's Company MFA policy can reject delegated MFA and require direct sign-in. Verified delegation satisfies the MFA check; existing employer, accounting, payroll and resource permissions still apply. Authenticator management, SSO linking and directory/security mutations retain direct sign-in requirements.

Deploy the Connect MFA migration and code on both sides using the existing fleet update process. See [Lightek Connect setup and acceptance](integrations/lightek-connect.md#verified-agency-mfa-handoff) for lifetimes, operator controls and test steps.
