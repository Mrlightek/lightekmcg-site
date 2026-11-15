# Inquiry intake and sales follow-through

Open **Dashboard → Sales & CRM → Inquiry inbox** for new interest, and **Tasks** to manage the promises your team needs to keep. The selected business website remains the boundary for every inquiry, lead, task and source rule.

## Review an existing website inquiry

1. Open Inquiry inbox and find **Unreviewed form submissions**.
2. Choose **Review inquiry**. The original form answers stay visible beside editable sales fields.
3. Confirm the person's name and email. Add company, phone and message where available. If company is blank, the person's name becomes the sales account label.
4. Choose **Accept & schedule follow-up**.

A new email creates a lead using the existing source-routing rules. A matching email links the existing lead without changing its name, owner, stage, notes or previous conversations. Each accepted inquiry adds its own attributed activity and one follow-up task due 24 hours after acceptance. The new lead also receives a next step and follow-up date for tomorrow.

If the lead was already converted, the task is attached to its existing deal. A new inquiry does not reopen a lost deal or change a won deal's financial state. Opening the retained lead provides the link to that deal.

**Ignore this inquiry** keeps the original submission and records who ignored it. Ignored entries are visible in the Ignored queue and are not automatically accepted later. Accepted entries cannot be ignored. This release retains intake history rather than offering destructive deletion or an undo/reopen operation.

Sales requires a usable email address. Phone-only website submissions can be staged and reviewed, then accepted when the reviewer has an email address. An inquiry does not reserve an appointment, take payment, create a platform account or grant marketing consent.

## Stage a CSV

Upload a UTF-8 CSV with one header row. Required headers are `name,email`; optional headers are `company,phone,message,source`. Header names are case-sensitive, may appear only once, and must come from that list.

```csv
name,email,company,phone,message,source
Jamie Buyer,jamie@example.com,North Studio,,Interested in managed streaming,event
```

Limits: 1–100 data rows, 512 KB per file, and 2000 characters per value. Accepted lead fields retain their tighter name/company, email and phone limits. Invalid emails can be staged for correction; they cannot become leads until corrected.

Uploading only creates review entries. Accept each row after review. Uploading the identical file again reuses the same entries, including already accepted or ignored rows. A different file containing the same email gets a distinct inquiry entry, then links the existing lead when accepted. Original CSV values remain separate from reviewed fields.

## Enable automatic intake for a published form

Website owners and account managers authorized to manage that website can configure automatic acceptance. A delegated Marketer/Manager can work the inbox and tasks, but cannot change automatic source rules solely through that membership.

1. Publish an installed website starter form on this business website.
2. In Inquiry inbox, find **Automatic form intake** and choose the published form.
3. Map Name and Email to actual form fields. Map Company, Phone and Message if the form provides them.
4. Set the lead source, such as `website`. It matches the source names in **Lead routing**.
5. Choose Enabled and save. Automatic intake starts with submissions received after enabling.

Only that exact website/template/section combination is connected. Existing submissions remain manual review items. Re-enabling after disabling starts a new activation window; it does not silently accept older submissions.

Valid new submissions create or link leads and schedule a task. Incomplete field mappings, invalid lead data and package-denied processing leave an entry in **Needs review** with an explanation. Correct the reviewed fields and accept manually when access permits. Rule changes apply to future captures; an already-staged entry retains its captured values for explicit review.

Use **Disable automation** beside an enabled rule to stop it, including after its page has been unpublished. Configuration never grants a new user access to a website or substitutes for the selected account's Commerce package permissions.

Automatic intake uses the existing Sidekiq queue. The five-minute recovery sweep finds eligible submissions whose initial dispatch was interrupted and pending work interrupted before acceptance. It processes at most 100 missing and 100 pending submissions per rule per sweep. Needs-review entries wait for a person, rather than being retried repeatedly. Repeated delivery reuses the same intake entry, lead and task; it does not charge another successful package write. Background processing uses the current website owner's site authorization and Commerce package allowance.

## Schedule and finish a task

Open a lead, deal, company or contact. Under **Follow-up tasks**, enter a concrete action, eligible assignee and due time. Times use the application time zone shown on the form.

- **Today** shows open tasks whose due time has arrived, alongside the existing lead/deal follow-up worklists.
- **Tasks** lists open work, earliest due first. Switch to Completed or Canceled to review historical work. The owner filter applies to tasks as well as the pipeline.
- **Mark complete** records who completed the task and when, with a timeline event on the associated sales record.
- **Snooze** chooses a future due time and records the reschedule in that timeline.
- **Cancel task** removes it from open work and retains its history.

A completed or canceled task is final in this release; schedule another task for the next action. Completing a task does not modify a deal stage or erase the lead/deal's next step. Review those fields deliberately after the conversation.

The assigned person must have sales access when the task is created. If their membership is later revoked, the website team can finish or cancel the task while retaining its original assignee as history. Revocation does not give that person continued access.

These are in-app due reminders: they surface when Today/Tasks is opened or refreshed. This release does not send reminder emails, send customer messages, create invitations or run an external calendar synchronization.

## Add to calendar

Choose **Add to calendar** on a task to download an `.ics` file. It contains a 15-minute follow-up event at the due time, with a stable task UID and its current status in the description. It has no attendee or invitation. Import it into your calendar manually.

The file is a snapshot. Changing, completing, snoozing or canceling a task does not update an already imported calendar event automatically. An export from a canceled task contains a canceled event status. The UID incorporates website/task identity and creation time so independent client instances do not collide on a numeric task ID.

## Deployment and verification

Run `db:migrate` and restart the web/Sidekiq processes through the existing deployment pipeline. The new migration adds intake rules, review entries and tasks. Existing website inquiries, Marketing contacts, sales records and consent fields remain authoritative. No source rule is enabled by default. Sidekiq loads `lightek_sales_intake_recovery` from `config/schedule.yml` on worker startup.

```sh
SALES_PREVIEW_DIR=tmp/sales-preview ruby test/standalone/sales_intake_checks.rb
SALES_PREVIEW_DIR=tmp/sales-preview node test/javascript/sales_crm_browser_test.cjs
ruby test/standalone/starter_library_http_checks.rb
```

The CRM/intake acceptance harness runs real migrations, installed starter-form parsing, model callbacks, jobs, transactional services, controllers and native views using SQLite. Private engine authentication/layout, the website ownership resolver and installed-package account storage are fixture boundaries. It checks job authorization/reservation calls and retry accounting against that boundary; it does not claim a production package quota test. The existing public form HTTP suite verifies the published-host boundary, validation, CSRF and rate limiting. Browser checks cover the native Today, pipeline, deal, inbox, inquiry-review and task screens at 1440/1024/390 pixels. PostgreSQL contention, production session/MFA, queue restart/recovery and independent client deployment require host acceptance.

Published catalog quotes now connect approved deals to pending orders and the existing payment/delivery flow; see [quotes to delivery](quotes-to-delivery.md). Email/calendar synchronization, automatic email outreach, configurable sales stages, quotas, forecast snapshots and negotiated pricing remain subsequent work. See [the CRM completion sequence](crm.md#crm-completion-sequence).
