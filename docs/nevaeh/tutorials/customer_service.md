# Customer Service SME

## Open a case

Customers open Customer Service & Billing in the Dashboard. Each signed-in account can create and read its own cases and reply to them. A reply on a resolved case reopens it. The customer conversation includes Nevaeh's updates, the customer's messages, and replies staff explicitly share.

Nevaeh processes new cases from the ticket backlog. She routes account or product questions to Customer Service, technical cases to Technical, and invoice questions and disputes to Accounting & Billing. When she verifies a supported billing lookup or an installation status that does not require Technical intervention, she saves the evidence, replies in the conversation, and marks the case resolved. Other cases stay open for the assigned team. A recurring backlog sweep recovers cases when the initial enqueue fails.

## Work the support queue

Employees can open the Customer Service queue from Tickets. Choose “Show this reply to the customer” to publish a reply in the case. Ordinary employee notes and execution evidence are internal.

Ask Nevaeh to “review customer support cases” or run `/operations customer_service`. This staff-only review returns unresolved case IDs, categories, teams, and dates. Case intake does not grant Nevaeh authority to run arbitrary commands from customer messages.

## Guided resolution and follow-up

Customer Service & Billing offers guided answers for finding purchased services and managing sign-in security. Nevaeh records which guide she used, posts the answer, and closes the case. Customers can reply to reopen it and reach the Customer Service queue.

Set `NEVAEH_SUPPORT_MAILBOX_ID` to the authorized, sending-ready Lightek Mail mailbox for this installation to enable outbound case updates. The worker scans recent replies every 15 minutes and queues a generic sign-in link for the latest customer-visible update. It checks the account and recipient again before submission. The Mail Studio message status shows whether the notification queued, sent, failed, or needs review. Case text and billing amounts stay in the Dashboard.

## Find purchased services

Open Your workspace → Your services. My applications lists purchased installations, and My reservations shows your bookings.

## Manage sign-in security

Open Your workspace → Your account → Sign-in security to manage your authenticator. Use a saved recovery code if you lose access to the authenticator.
