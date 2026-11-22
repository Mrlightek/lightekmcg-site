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
- Open **Shared files** inside a Team Chat channel to co-edit documents, formula spreadsheets, or browser presentations. Spreadsheet exports contain calculated CSV values. Documents export as text and slides export as source. This editor uses revision checks to protect concurrent saves. For cross-installation collaboration, open **Shared files** on a connected Network channel. Both sides edit one copy on the hub. File access follows channel membership, and disconnect archives the host’s copy and removes partner access.

## Shared team channels

An organization owner can use **Create shared channel** in Team Chat and enter the account email of another organization owner on the same Lightek installation. The receiving owner reviews and accepts the invitation in Team Chat. Each owner can add active teammates from their own workforce directory. Shared history and the participant list identify the organization for each message or teammate.

Either owner can disconnect the organizations. Partner access to the channel and its history ends at disconnection. The host keeps its record. A new invitation creates a fresh channel. Offboarding also removes access through the affected organization.

### Channels across installations

Open **Network channels** from Team Chat on a managed installation connected to the Lightek hub. The inviting owner enters the other installation's hostname or branded Lightek mailbox. The receiving owner accepts inside their own Dashboard. Each owner can add active coworkers, and the message timeline identifies the sending installation. The hub stores the conversation. Disconnecting removes the partner's access while the inviting owner retains its history.

### Installation email

Finishing owner password setup queues creation of the installation's own branded mailbox. Existing installations can open **Mail Studio → Open your installation mailbox** to provision or access it. The address belongs to the installation's owner and is distinct from a personal Lightek member address. Read, compose, and check queued delivery from the installation mailbox.

Use **Mail Studio** settings for mail on domains you own. Add and verify your domain and create mailboxes for it. Custom-domain mail uses that installation's existing DNS and mail transport configuration. The branded installation mailbox uses the Lightek hub's verified mail domain and delivery service.
