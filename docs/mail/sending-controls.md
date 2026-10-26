# Lightek Mail sending controls and private server setup

This extends PR #117. It does not enable a paid mailbox offering or switch the existing application's Gmail delivery setting. The new database policy starts with all Mail Studio sending stopped, including existing enabled mailboxes. Run both migrations through normal deployment.

## Recipient allowances

Limits count unique envelope recipients, not messages. A message to five recipients uses five units. Reservations are made in the same database transaction as queuing. A separate dispatch timestamp enforces the same rolling limits again immediately before SMTP, so an old backlog cannot burst through after a pause. Throttled queued messages are rescheduled without attempting SMTP or consuming another acceptance reservation. All reservations use the same policy row lock, then the mailbox row lock, to prevent simultaneous workers exceeding customer or server budgets. Message deletion does not release reservations. Failed/scanner-blocked submissions consume their reservation; retrying the same API idempotency key does not consume another reservation.

| Scope | Rolling minute | Rolling hour | Rolling 24 hours |
| --- | ---: | ---: | ---: |
| New mailbox | 5 | 25 | 100 |
| Customer, across their mailboxes | 10 | 50 | 200 |
| Entire central application | 25 | 100 | 500 |

Existing mailboxes retain their configured daily limit; the new default is 100. Super admins can edit mailbox allowances in Mail. Customer/server limits use `LIGHTEK_MAIL_CUSTOMER_MINUTE_LIMIT`, `LIGHTEK_MAIL_CUSTOMER_HOUR_LIMIT`, `LIGHTEK_MAIL_CUSTOMER_DAY_LIMIT` and the corresponding `LIGHTEK_MAIL_SERVER_*` variables. Invalid or nonpositive values reject submissions. These are conservative launch settings; raise them deliberately after observing legitimate traffic and delivery reputation. They are not a guarantee of inbox placement.

Browser compose, HTTPS, draft sends and automatic replies all call the same reservation service. The HTTPS adapter and API accept To, Cc, Bcc and up to ten base64-encoded attachments within the 10 MB decoded message limit. Each distinct To/Cc/Bcc recipient counts toward limits. The adapter rejects a custom SMTP envelope that differs from the union of those recipient lists and rejects multiple From addresses. Bcc recipients must remain private in delivered MIME headers. Native SMTP clients on 465/587 are not enabled by this release.

## Required outbound scanning and abuse feedback

Before SMTP, each worker submits the MIME message to a loopback-only Rspamd `/checkv2` endpoint. `LIGHTEK_MAIL_RSPAMD_URL` defaults to `http://127.0.0.1:11333/checkv2`. Unavailable/malformed scans and temporary deferrals keep the message queued for a delayed retry without SMTP; explicit spam rejections fail the message. A rejection or score of at least 6 blocks the message and suspends sending across the customer. New mailboxes created by a suspended customer stay blocked. The default scanner policy is deliberately conservative and can require manual review of legitimate messages.

The worker rechecks the server/customer stop after scanning. An SMTP transaction already in progress, or mail already accepted into Postfix, needs separate queue handling; an application flag cannot recall mail.

`POST /api/lightek-mail/feedback` accepts operational feedback with a separate `X-Lightek-Mail-Feedback` secret matching `LIGHTEK_MAIL_FEEDBACK_TOKEN` (at least 32 random bytes). Mailbox sending tokens do not authorize feedback. Supply `message_id` (the Lightek record ID), `kind` (`hard_bounce`, `complaint` or `spam`) and a stable `event_key` of 8–100 letters/digits/underscores/hyphens. Repeated event keys are deduplicated; repeated bounce reports for one message count as one bounced message.

One trusted complaint/spam report suspends the customer. Hard bounces suspend the customer after at least 20 recipient reservations and five distinct bounced messages in 24 hours, when bounced messages divided by recipient reservations is at least 10%. Three distinct complained-about messages within one hour stop the entire application's new sending. These initial thresholds count bounced messages conservatively; a multi-recipient message can have several recipient failures. Feedback events can also be recorded by the operator with `bin/rails 'lightek_mail:feedback[MESSAGE_ID,hard_bounce,PROVIDER_EVENT_KEY]'`.

The authenticated feedback receiver is implemented, but live Postfix DSN/complaint-provider ingestion still needs a trusted adapter and end-to-end verification. Do not forward arbitrary inbound messages claiming to be bounces or complaints into that endpoint. HTTP scanning and MTA scanning can both consume conservative Rspamd token-bucket allowances; PostgreSQL reservations remain the application source of truth.

Operator controls (run as the application user with the production environment loaded):

```bash
bin/rails 'lightek_mail:pause[Investigating outbound traffic]'
bin/rails 'lightek_mail:resume_customer[USER_ID]'
bin/rails lightek_mail:resume
```

Customer resume clears only the reviewed customer's suspension; it does not clear rolling allowances or a server stop. For an incident affecting mail already queued at Postfix, root can hold the queue with `postsuper -h ALL`. Inspect the affected messages before individually releasing them. Do not automatically release all held mail.

## Verify before merge/deployment

Run `bash lib/scripts/verify_lightek_mail.sh` in the real application checkout with its private gems and PostgreSQL available. It prepares the test database, checks Zeitwerk, runs native host service/HTTP tests (including real session login), and runs the Python helper tests. It does not send to outside recipients or change production mail configuration.

The standalone `test/support/lightek_mail_fixture.rb` harness exercises the actual mail classes against a minimal Rails application, including raw inbound MIME, SMTP protocol handling, HTTP recipient/feedback boundaries and sending controls. It has a fixture User and does not validate host authentication, entitlements or engine integration. CI runs this harness against PostgreSQL without private repository credentials and validates the private mail-server bootstrap separately. It must not be represented as a native application pass.

Native CI jobs still require the `LIGHTEK_CI_APP_ID` secret/variable and `LIGHTEK_CI_APP_PRIVATE_KEY` secret. The GitHub App needs read-only Contents access to the private `lightekmcg` dependencies, and its credentials must be available to this repository's Actions jobs. No credentials are embedded in code and no failing native check is skipped. The workflow now supplies test PostgreSQL/Redis services and reports missing credentials explicitly.

## Fresh Ubuntu 24.04 mail server

The supplied server report showed no Postfix/Dovecot/OpenDKIM/Rspamd units and no listeners on 25/465/587/993. Use the fresh-server path only if that remains true. The installer refuses to overwrite detected Postfix/Rspamd configuration or occupied mail/scanner ports.

Inspect a plan without changing services:

```bash
python3 lib/scripts/lightek_mail_server.py plan --output /tmp/lightek-mail-plan
```

On the mail VPS, after obtaining this PR's checkout, root can run:

```bash
python3 lib/scripts/lightek_mail_server.py install
python3 lib/scripts/lightek_mail_server.py dkim --domain lightekmcg.com
```

The installer adds Postfix, Rspamd and a dedicated persistent Redis service on loopback port 16379, without replacing the application's Redis configuration. Rspamd handles DKIM signing, so a separate OpenDKIM daemon is unnecessary for this topology. Dovecot is deferred because this release stores webmail in Rails/Active Storage and does not provide an IMAP mailbox backend.

Postfix binds loopback only, has an empty sender allowlist, disables local `sendmail` injection, defers external SMTP transport, rejects unauthorized relay and requires its Rspamd milter. The scanner/controller/Redis ports are private; the controller is disabled. Rspamd has additional sender and source-IP token buckets with recipient multipliers. SMTP pacing limits destination concurrency to two and adds a one-second destination delay. The installer creates no inbound catch-all, opens no firewall ports, publishes no DNS and enables no customer account.

DKIM generation preserves existing keys, writes a real 2048-bit private key readable by Rspamd, and prints only the public TXT record. Publish the record for each customer domain; never copy private keys into chat or DNS.

Public SMTP activation remains a separate live deployment step: configure verified recipient maps and the documented Action Mailbox pipe, exact sender maps, MX/A/PTR/SPF/DKIM/DMARC, TLS certificates, trusted feedback ingestion, queue monitoring/recovery and an authenticated end-to-end delivery test. Only then expose inbound port 25, release SMTP transport deferral and resume application sending. Keep 465/587/993 closed until their authenticated client services exist. A bootstrap pass alone does not establish deliverability.

References: [Rspamd outbound scanning](https://docs.rspamd.com/tutorials/scanning_outbound/), [rate limits](https://docs.rspamd.com/modules/ratelimit/), [DKIM signing](https://docs.rspamd.com/modules/dkim_signing/), and [Postfix relay controls](https://www.postfix.org/SMTPD_ACCESS_README.html).
