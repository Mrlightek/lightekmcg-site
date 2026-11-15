# IT-first business operations

Lightek is IT operating software that provides business products. Business users must be able to complete their work; IT must be able to inspect the authority, execution, failure and recovery paths behind that work from the same system.

This is a product/engineering contract for continued implementation, not a claim that every existing module already satisfies every point.

1. **Usable business action:** expose the outcome in the native workspace with clear ownership, current status and the next action.
2. **Explicit authority:** separate HR, IT, financial and account-owner permissions. Review access at execution, not only when showing a menu.
3. **Authoritative records:** retain the business record and the worker/provider references that explain its state. A redirect, optimistic label or log line is not proof of payment or delivery.
4. **Native operator evidence:** make receipts, diagnostic events and related records reachable inside Dashboard. Operators should not need to reconstruct an ordinary business process from server files.
5. **Safe recovery:** distinguish what succeeded from what remains. A retry must not repeat a charge, grant access again or erase history.
6. **Lifecycle and continuity:** activation is reviewed, departures revoke access, open work receives an owner, and customer/financial records survive staff or agency changes.

## Current concrete examples

| Business workflow | Business surface | IT/operator evidence and recovery |
| --- | --- | --- |
| Employee/agency onboarding | People → Onboarding & offboarding | Scoped checklist authorities, inactive new memberships, explicit activation, actor/evidence/version history |
| Employee/agency departure | Offboarding case | Committed revocation receipt, session/token/grant changes, retained clients, failed-record IDs, repair link and handoff retry |
| Sale to delivered service | Sales deal → quote → customer checkout | Immutable revision, approval channel, order ID, verified payment state and fulfillment/provisioning references |
| Inquiry follow-through | Inquiry inbox and Tasks | Original source, duplicate-link result, assigned owner, task timeline and queue recovery |

Use **Dashboard → System logs** for diagnostic events, then follow the referenced business record. These new events carry lifecycle-case IDs or quote/order IDs. A universal cross-module correlation scheme and automatic external credential cleanup are not implied by this release.

Related operating guides: [onboarding/offboarding](../people/onboarding-offboarding.md), [quotes to delivery](../sales/quotes-to-delivery.md), [inquiry follow-through](../sales/intake-and-follow-through.md).

Growth Foundation applies this contract with visible campaign/source lineage, unknown-source reporting, brief revisions, reversible link enable/disable, structured diagnostic events and links to the native inquiry, deal and order recovery workflows. See [the operating guide](../sales/growth-foundation.md).
