# Employee and agency onboarding/offboarding

Open **People & access → Onboarding & offboarding**, or **Agency workspace → Agency onboarding & offboarding**. Select the business/employer account. The case records its preparer, checklist evidence, step actors, revocation actor/time, handoff receipt and final completion actor.

## Employee onboarding

1. Use the person's existing Lightek account, then add the team membership in People. This does not change that person's platform role or take over their account. Existing account creation/first-password setup remains the identity entry point.
2. New memberships are now staged inactive and automatically receive an employee-onboarding case.
3. HR/People administration records identity, role/start-date/document review and orientation evidence.
4. IT/Directory administration records equipment and least-privilege access review.
5. IT completes ordinary onboarding within the membership's start/end dates. Activating HR/IT/payroll/accounting/compliance administrative roles requires the employer owner; platform super-admins retain explicit system authority.

The case activates only this employer membership. Other employers, independent business ownership and the person's platform role remain separate. Membership creation/activation cannot use the old Active checkbox to bypass this workflow. Existing active memberships are retained during upgrade.

Cancel an unfinished onboarding case without activating it. A replacement case can be prepared later. Only one open lifecycle per employer/subject is allowed, so a canceled onboarding cannot later be completed accidentally.

## Employee offboarding

1. Prepare Employee offboarding for the selected membership.
2. IT/Directory administration reviews the impact, checks the confirmation and chooses **Revoke access & hand off work**. HR preparation alone does not execute privileged revocation.
3. The application disables the membership, removes its HR/IT/finance responsibilities, revokes its individual resource grants and removes delegated website memberships within that employer/account tree. Department grants remain as organizational policy, but the inactive membership no longer receives them.
4. Existing application sessions are removed and the API token is rotated. A dedicated `employee`/`contractor` platform account is suspended if it has no other active employer memberships. Business-role accounts and other employer memberships are preserved.
5. Active leads, open deals, company/contact sales ownership, source routing and open tasks are handed to each website's business owner. Closed deals, converted leads and completed tasks retain historical attribution.
6. HR/IT finish the handoff, equipment/external-access and final-payroll/benefit/retention checklist with evidence, then close the case.

A termination end date is retained/set for already-started employment so historical worked-period/payroll records remain usable. No pay statement, payout, bank destination, benefit history or customer record is deleted. Final pay, benefits and provider-side credentials are reviewed through their existing workflows, not guessed or canceled automatically.

Setting a date by itself is not this coordinated offboarding operation. Use the lifecycle action for immediate membership/session/token revocation and open-work handoff. The workflow does not kill running renders/jobs or terminate existing external OS/VPN/device sessions. Membership changes dispatch the existing DirectorySyncJob; IT must verify the result and record external cleanup evidence.

Independent ownership and legitimate permissions from another employer or separate agency contract are not silently removed by ending one employment relationship. Review those relationships as part of the checklist.

## Agency onboarding

Promoting a client to an agency now prepares an onboarding case for its direct upstream account. Legacy agencies with no lifecycle record continue operating. The upstream owner reviews business/terms/billing, branding/packages/support and MFA/Connect/client-management responsibilities.

While onboarding is open or canceled, the account can retain its own business/profile access but cannot gain delegated client management, new client creation or Connect access through the agency role. Completing the latest onboarding enables those agency-management capabilities. Starting onboarding for an existing agency temporarily gates client management; it does not stop the clients' sites or services.

A canceled agency onboarding stays gated until a replacement is completed. Re-onboarding after agency offboarding can clear a lifecycle-created agency suspension after upstream review. Revoked sessions, API tokens and Connect credentials are never restored; establish new authorized sessions/connections.

## Agency offboarding

The direct upstream owner or a platform super-admin executes revocation. The agency login is suspended, sessions/API credentials are invalidated and its Connect connections are revoked. Agency-owned employee memberships also lose employer-scoped access; affected staff sessions/tokens and delegated site memberships are revoked, with role-specific suspension rules as above. Platform super-admin accounts remain protected.

Client accounts, their own employee organizations, site ownership, server instances and customer services are retained. On agency-owned sites, the upstream owner receives a manager membership when needed to take over open work; on client-owned sites, handoff targets that client's owner. Agency-owned form-intake automation is disabled, while independently owned client intake rules are preserved.

This operation does not reparent accounts, cancel hosting/subscriptions, change revenue terms, waive balances or run payments. Existing order/subscription snapshots remain authoritative. Use the retained agency/client management and billing tools for any reviewed contractual or ownership changes, and record the decision in the case checklist.

## Recovery and operator evidence

Access revocation commits before business-data handoff. A malformed sales record cannot restore a departed person's access by rolling the entire operation back. If handoff fails, the case remains **Access revoked**, with **Needs attention**, the failing record type/ID/site where available, and a repair link. An authorized operator fixes the record, chooses **Retry open-work handoff**, and then completes the checklist. Completion is blocked while handoff remains unresolved.

The receipt distinguishes security revocation from business handoff; repeated revocation/retry does not duplicate ownership changes. Checklist edits and critical transitions require the current case version. Runtime authorization is rechecked at mutation boundaries so a cached staff workspace cannot write after revocation.

Structured application events use `lightek.lifecycle.*` with case, employer and actor IDs. Operators can inspect the case and **Dashboard → System logs** (`/dashboard/system_logs`) without searching the server for the business record. Logs are diagnostic; the case/membership/session/grant records are authoritative. No passwords, tokens or checklist evidence are written in these structured events.

## Delivery and verification

Run migrations and restart web/workers normally. Existing users are not suspended or bulk-enrolled by the migration. New membership creation and agency promotion use the coordinated flows; existing inactive memberships can be prepared for onboarding from the lifecycle workspace.

`test/standalone/lifecycle_quote_checks.rb` exercises the real policy/services/models/migrations and native HTTP views. Private engine authentication/MFA, remote directory/device providers and hosting-provider execution remain integration boundaries; verify those in the deployed environment before treating external revocation as complete.
