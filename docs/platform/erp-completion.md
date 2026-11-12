# ERP completion and acceptance

The target is a complete ERP and accounting suite centered on Dymond Bank. Use the same website/account, customer, order, invoice, payment, reservation, media and provisioning records throughout. A workspace counts as delivered when an authorized user can finish its business process and recover from an error through Dashboard.

## Connected creative work delivered here

- Business, Design & Content, articles, Studio, campaigns and commerce show the same website identity and workspace links. Links preserve `site_id`; destination controllers continue to enforce access.
- Studio opens inside Dashboard. Focus mode is an explicit toggle; Escape returns to Dashboard without recreating the editor or discarding drafts.
- Save a campaign, then choose **Create / open in Studio** from its editor. The existing Studio project creation service creates an editable production, seeds the script from the campaign brief, and uses portrait for social campaigns. Reopening uses a stable request key for that campaign and actor. Collaborators keep independent productions; retries preserve existing edits. The Studio header links back to the campaign.
- This handoff creates no render, payment, publication or third-party submission. Finished media still uses the existing Deliver/release path. Automatic selection of a completed master as campaign media is a subsequent handoff; it must preserve authorization and satisfy each destination's media requirements.

## Accounting work to close

This inventory describes **host integration evidence**, not the full capabilities of the private Bank gem. `Gemfile.lock` pins Dymond Bank to `06153f7c90583c06005c08d153cd1978e77d8b35`. Its source must be checked before implementing or duplicating financial primitives. The connected GitHub source lookup returned 404 during this change, so ledger APIs have not been verified from that dependency.

| Workstream | Existing integration to extend | Acceptance required for completion |
| --- | --- | --- |
| Customer billing and receivables | Marketplace Bank invoices/purchases; commerce orders; subscription events and `BillingInvoice` | Invoice lifecycle, partial/overpayments, credits, aging, collections and customer statements reconcile to authoritative payment records |
| Double-entry general ledger | Dymond Bank transaction/settlement boundary; `LightekMarketplace::InvoiceSettlement` validates invoice/charge matching | Verify existing Bank posting interfaces; account chart, balanced immutable entries, idempotent source posting, reversals, currency boundaries, permissions and period close |
| Payment and bank reconciliation | Processor payment/webhook verification, refunds, merchant payouts and revenue allocations | Trace order → invoice/payment → fees/refund/transfer → ledger → processor/bank statement; unmatched items visible with review and recovery; replay never duplicates a posting |
| Payables and purchasing | Existing account hierarchy and suppliers to connect to Bank billing | Supplier records, purchase orders, receipts, bills, approval/payment workflow, credits and aging share the ledger and inventory records |
| Financial reports and close | Existing operational sales/refund and subscription views | Trial balance balances; balance sheet, profit/loss and cash-flow reports drill into posted entries; closing periods prevents backdated mutation and supports audited adjustments |
| Inventory and fulfillment | Products, variants, order items, fulfillment, shipping quotes/labels | Stock movements, returns, valuation and cost of goods reconcile to fulfillment and accounting; retries never double-decrement inventory |
| Tax, workforce and business operations | Existing product pricing, billing, accounts and permissions | Explicit jurisdiction/payroll scope, tax liability and remittance records, expenses, projects/time and approvals, audit export and role separation |

Sequence the work from verified Bank contracts to ledger/source posting, reconciliation, receivables/payables, inventory valuation and financial close. Extend business operation modules against those contracts. Operational sales totals are useful in Business Command Center; they must not become an invented bank balance or financial statement.

## Verification for this change

- `test/standalone/campaign_studio_checks.rb`: real AR/Studio workers and controller HTTP requests; brief and output format, idempotent reopen, edited script preservation, cross-account denial, collaborator permission, CSRF and native workspace rendering. Private engine layout/authentication are test boundaries.
- `test/javascript/studio_dashboard_context_test.cjs`: exported controller-rendered workspace; production scripts with scoped API fixtures; 1440/1024/390 widths, site navigation, campaign return link, embedded and focus layouts, draft retention and leave warning. The surrounding private Dashboard layout is a fixture.
- Existing Studio production and site-content suites remain regression checks. External neural generation, Blender rendering and live social delivery require their own production acceptance.

Run the context browser check after exporting its native view:

```sh
STUDIO_WORKSPACE_PREVIEW_DIR=tmp/studio-context ruby test/standalone/campaign_studio_checks.rb
STUDIO_WORKSPACE_PREVIEW_DIR=tmp/studio-context node test/javascript/studio_dashboard_context_test.cjs
```

No database migration is required for this handoff. The stable request key uses the existing project uniqueness/creation path; campaign identity and the initial brief live in the existing scene settings alongside its editable timeline.
