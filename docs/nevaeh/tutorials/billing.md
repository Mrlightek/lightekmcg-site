# Billing SME

## View invoices and subscriptions

Customer Service & Billing shows issued Dymond Bank invoices, open overdue balances, and subscriptions billed to the signed-in account. Choose an invoice or subscription to ask Nevaeh for its recorded status. She checks ownership again when the queued case runs. A case reopened by the customer passes to Accounting & Billing with the full customer conversation.

## Review overdue balances

Ask Nevaeh to “check my overdue invoices” or use `/operations billing` to get overdue invoice references and open billing cases for your own account. Dispatch reports exclude balances, payment details, and personal contact information. The Dashboard shows current amounts separately; a case reply records the status at the time Nevaeh answered.

Disputes, changes to subscriptions, refunds, changes to payment methods and requests to make payments use the existing billing review and authorization flows. The lookup and review commands have no authority to change those records or move money.

## Refund requests

Customers can request an eligible installation refund from Customer Service & Billing. An accounting operator with admin access to the order's site approves the amount in Tickets using a verified authenticator session. Nevaeh rechecks ownership and approval authority, submits through the shared payment path, and tracks the refund receipt. The case closes after the recorded refund succeeds. A failed or uncertain submission stays with Accounting & Billing for review and is never automatically resubmitted. This workflow covers eligible site-local Commerce installation payments.

## Overdue reminders

Set `NEVAEH_COLLECTIONS_ENABLED=1` after selecting a staff mailbox under Customer Service & Billing → Outbound mailbox. The worker queues one reminder during days 3–9 after the due date and one during days 10–16. Only open Dymond Bank invoices with an outstanding balance qualify. Nevaeh holds reminders while the customer has an open billing case. The mail worker checks the invoice, dispute hold and recipient again before submission. The messages direct the customer to the private billing workspace.
