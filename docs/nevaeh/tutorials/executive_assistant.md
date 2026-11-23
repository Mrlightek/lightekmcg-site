# Nevaeh as executive assistant

Nevaeh supports Lightek's CEO across company operations, communications, scheduling, and production. Keep executive material in the CEO's account, route team work to the appropriate organization and channel, and use existing permissions and receipts for actions.

| Responsibility | Lightek workflow |
| --- | --- |
| Brief the CEO and surface decisions | Open **CEO Desk** or ask “Give me my CEO brief.” The brief reads live provisioning approvals, blocked goals, urgent tickets, due sales follow-ups, paid orders, executive agenda entries, unread counts from mailboxes owned by the CEO, and personal reservations. |
| Coordinate meetings, personal commitments, and deadlines | Use **Private agenda** to add, edit, or close entries for work meetings, personal or family appointments, travel, screenings, and follow-ups. Entries can carry private notes. Saving shows overlapping commitments. Ask “What is on my CEO agenda?” for a rundown that omits notes. |
| Add an agenda entry conversationally | Say `Add a meeting called "Launch review" to my CEO agenda from 2026-11-30T14:00 to 2026-11-30T14:30`. Nevaeh uses the installation time zone for local times and returns a link to the saved entry. The same command accepts an ISO time with a numeric offset. |
| Manage communications | Use Lightek Mail to read and search mail, draft replies, and review delivery status. Nevaeh's existing mail actions can search, flag, or draft email for a specified mailbox. Sending a draft uses the separate confirmation command. |
| Coordinate departments and projects | Use **Team Chat** for company-wide discussions and invite-only channels. A channel carries message history, replies, and search. Channel access follows active workforce membership. |
| Plan travel, screenings, and follow-up | Track the commitment on the private agenda and use the existing Reservations, Rooms, Studio, Sales, or Accounting workflow where applicable. |

## Executive work and shared files

- Open **Executive work** to create a follow-up, call, travel, expense, contract, or screening item. A due item produces a Dashboard notification for the CEO and the active assignee. Route supporting files to a teammate, record their review, and save a completion reference and confirmation file when applicable. Closing an expense or contract requires a completed review. The CEO brief includes due work.
- To add a work item through Nevaeh, say `Track travel "Atlanta production meetings" for my CEO Desk by 2026-11-30T14:00`.
- From **Private agenda**, download a calendar file or send an invitation, update, or cancellation through an owned Lightek mailbox. Use the same organizer address for the event. Private agenda notes stay in the agenda. Mail Studio reports delivery status. External availability and RSVP collection require separate calendar integration.
- In **Executive work**, connect a phone gateway with a signing secret and optional active assignee. The callback accepts missed-call and voicemail events. The gateway sends JSON keys `event_id`, `kind` (`missed` or `voicemail`), optional `caller`, optional `summary`, and optional boolean `urgent`. Send the Unix timestamp in `X-Lightek-Timestamp` and the lowercase hexadecimal HMAC-SHA256 of `timestamp.raw_request_body` in `X-Lightek-Signature`. The installation needs a configured gateway to receive live calls.
- For travel, send a booking request to an approved booking desk. Record the provider's itinerary or booking reference and attach the confirmation to finish. A queued message is a request. For direct flight and hotel booking, open **Direct travel booking** from the trip, connect a Duffel account, and search for flights or hotels. Flights use airport codes and hotels use coordinates. You can also load an existing flight offer or hotel rate ID. The owner reviews the total, supplies one traveler’s details, and confirms the purchase. Reconcile uncertain results by supplier ID before retrying.
- For screenings, choose a valid web-screening license and send the attendee the protected Lightek viewing link. The existing screening endpoint rechecks playback rights. For a theater, open **Theater DCP delivery** from the screening case. Upload a prepared ZIP and record your theatrical rights reference. The signed-in theater contact receives a Dashboard notification, can download while the grant is valid, and can acknowledge the SHA-256. Archive checks do not establish server ingest or playback. Encrypted packages require a separate KDM workflow.
- Open **Shared files** inside a Team Chat channel to co-edit Action Text documents, formula spreadsheets, or browser presentations. Spreadsheet exports contain calculated CSV values. New documents use the Trix editor for headings, lists, links, and formatting and export as HTML. Older plain-text documents still open and can be edited in Trix. Slides export as source. Open the editor and Office autosaves content. Concurrent changes to separate text ranges can merge. For overlapping edits, the editor keeps your draft so you can reconcile it against the latest version. Open **Version history** to restore a prior save. For cross-installation collaboration, open **Shared files** on a connected Network channel. Both sides edit one copy on the hub. File access follows channel membership, and disconnect archives the host’s copy and removes partner access.

## Shared drives and calendars

- Open **Shared drives** from Team Chat or the Dashboard. An organization owner creates a drive and grants active teammates viewer or editor access. Editors can upload files up to 25 MB, create folders, rename or move items, and search by name. Editors can create and live-edit native Office documents, spreadsheets, and presentations directly in any drive folder. Drive viewers can read and export them. Team Chat channels also keep their own Office files. Spreadsheets open with an editable grid and preserve existing formulas and CSV exports.
- Open **Shared calendars** to schedule events, invite active teammates through Dashboard notifications, track RSVPs, and check shared-calendar availability. The organizer or owner can edit, reschedule, or cancel events. Use the calendar download to open an event in another calendar application. Personal CEO agenda entries are excluded from team availability.

## Shared team channels

An organization owner can use **Create shared channel** in Team Chat and enter the account email of another organization owner on the same Lightek installation. The receiving owner reviews and accepts the invitation in Team Chat. Each owner can add active teammates from their own workforce directory. Shared history and the participant list identify the organization for each message or teammate.

Either owner can disconnect the organizations. Partner access to the channel and its history ends at disconnection. The host keeps its record. A new invitation creates a fresh channel. Offboarding also removes access through the affected organization.

### Channels across installations

Open **Network channels** from Team Chat on a managed installation connected to the Lightek hub. The inviting owner enters the other installation's hostname or branded Lightek mailbox. The receiving owner accepts inside their own Dashboard. Each owner can add active coworkers, and the message timeline identifies the sending installation. The hub stores the conversation. Disconnecting removes the partner's access while the inviting owner retains its history.

### Installation email

Finishing owner password setup queues creation of the installation's own branded mailbox. Existing installations can open **Mail Studio → Open your installation mailbox** to provision or access it. The address belongs to the installation's owner and is distinct from a personal Lightek member address. Read, compose, and check queued delivery from the installation mailbox.

Use **Mail Studio** settings for mail on domains you own. Add and verify your domain and create mailboxes for it. Custom-domain mail uses that installation's existing DNS and mail transport configuration. The branded installation mailbox uses the Lightek hub's verified mail domain and delivery service.

## Importing Word documents into Shared Drives

In the destination folder, open **Import a Word document** and choose a standard `.docx` up to 5 MB. The imported file opens in the rich-text editor. The import preserves ordinary paragraphs, headings 1–3, basic bulleted and numbered lists, safe web and email links, and common emphasis. Table text becomes paragraphs. Images, page layout, headers, and footers stay in the original file. The editable text limit is 64 KB.

## Importing Excel into Shared Drives

In the destination folder, open **Import an Excel spreadsheet** and choose an `.xlsx` workbook up to 5 MB. The import creates a new editable spreadsheet within the drive. A workbook must have one worksheet that fits the Workspace grid (100 rows by 26 columns, up to 64 KB of editable content). Values and supported local formulas are retained. Save separate copies of individual worksheets for multi-sheet workbooks. Formatting, charts, and other workbook features stay in the original file.

## Repeating shared calendar events

Choose daily, weekly, or monthly repeat and enter 2–52 occurrences. Teammates RSVP to each occurrence. The organizer or owner can edit a single occurrence or cancel it and the remaining series. Monthly events use the last day of shorter months.

## Video meetings on shared calendars

On an upcoming event, choose **Add video meeting**. Select a website owned by the calendar's organization if prompted. The website must have Lightek meeting media configured, and the event must last 15–480 whole minutes. For a recurring event, add a meeting to each occurrence that needs one.

Organizers and invited teammates can open the meeting from Shared Calendars or their exported calendar event. Guests sign in and wait for the host to admit them. Moving the event before its meeting opens keeps the same link. Cancelling the event ends the linked room.

### Import a Drive export

Open a Shared Drive where you have edit access and select **Import Drive ZIP**. Choose the destination folder and preview the archive. The preview shows each path, editable Office conversions, downloads, duplicates, and conflicts.

Import a single ZIP up to 50 MB with up to 100 MB expanded, 500 total files and folders, and individual files up to 25 MB. Supported Word, Excel, and PowerPoint exports become editable Office files. Other files, including Office files outside the converter limits, stay available as downloads. Imported items follow the destination drive's access settings.

Select **Start import** and refresh the status as needed. The same archive can be imported again without making copies. Existing files at conflicting paths are left in place and shown in the report. A failed job can resume without copying files it already saved.
