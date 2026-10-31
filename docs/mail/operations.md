# Lightek Mail: central delivery, webmail and email templates

See [sending-controls.md](sending-controls.md) for the current recipient-based rolling limits, required outbound scans, default global stop, abuse feedback, fresh-server installer and pre-merge verification. Those controls supersede the original submission-count defaults described below.

## Deployment boundary

This change supplies the Rails mail product and authenticated HTTP submission/ingress. It does not claim that the live VPS already has a working mail transfer agent, DKIM signer, spam filter, correct DNS or working external delivery. It does not install or replace an existing mail daemon. Inspect the central server first with `bash lib/scripts/audit_lightek_mail.sh`; use that output to integrate with the actual Postfix/other MTA configuration. Existing Gmail delivery stays selected unless the operator changes `MAIL_DELIVERY_METHOD`.

Deploy through the existing deploy script; this adds database tables and uses the existing Active Storage and Sidekiq services. There are no new gems, containers, DNS mutations or public SMTP listeners. Open **Settings → Email & communications → Lightek Mail**, `/dashboard/mail`, or the email designer link in Design Studio.

## Recommended topology

Client application → authenticated HTTPS on the Lightek site → mailbox-scoped queue → central SMTP server → recipient mail server. Incoming SMTP → MTA/spam filter → authenticated HTTPS envelope ingress → Action Mailbox → durable Lightek inbox → optional automatic reply.

Use `mail.lightekmcg.com` for the central SMTP server hostname. The HTTPS submission API initially uses the existing application's TLS hostname `lightekmcg.com`, so this change needs no new Apache virtual host. These can be different hostnames. Blocked client instances need outbound HTTPS to the central application; the central sender needs working SMTP egress. Offering clients SMTP submission directly on 587/465 remains optional and needs authenticated TLS submission, per-client credentials and sender restrictions in the MTA. This implementation intentionally does not create an unauthenticated relay.

This is a central service first. Dedicated client mail servers can follow for isolation, scale or contractual requirements, with their own SMTP egress, DNS and reputation. A single central IP also means a shared reputation and operational failure domain; enforce mailbox limits and monitor the queue.

Action Mailer is the sender, Action Mailbox is the incoming processor. The Rails web inbox is the client UI. IMAP/POP access from Apple Mail/Outlook/Thunderbird requires an additional mailbox backend such as Dovecot and synchronization/provisioning; it is not implemented by Action Mailbox or this release. Calendar, contacts, advanced spam quarantine, mailbox migration, shared-team delegation, campaigns, delivery webhooks and billing fulfillment are separate work. HTTPS submission is not a telephone media/signaling implementation.

## Activate a customer

1. Grant the customer's existing user the `mail` feature entitlement: `bin/rails 'lightek_mail:grant_access[USER_ID]'` under the production app environment. Administrators and employees can already open Mail; all non-super-admin access stays scoped to the operator's own mailboxes.
2. The customer adds their own domain in Mail. It is globally unique and belongs to that business/user; this first release does not implement delegated seats inside another user's domain.
3. Publish the shown `_lightek-mail.DOMAIN` TXT ownership value, then verify in the UI. Domain ownership alone is not delivery readiness.
4. Create explicit mailbox addresses. New mailboxes are paused by default. A super admin configures sending/storage limits and enables the mailbox only once SMTP routing and domain signing/DNS are tested. Default limits are 1 GiB logical mail storage, 200 outbound submissions/day and 20 recipients/message. Daily reservation counts survive deletion of message history. They are technical defaults, not an automatically sold $25 plan. No Marketplace price or payment has been changed.
5. Publish and test MX, SPF, DKIM and DMARC for each customer domain. The SMTP IP should have forward-confirmed PTR matching the SMTP hostname. Generate real DKIM keys on the MTA; never publish invented keys or replace an existing SPF record with a second SPF record. Domain-specific signing is required for aligned customer mail.
6. Sync the enabled recipient list to the MTA after additions/removals or pauses. Unknown recipients should be rejected during SMTP RCPT rather than accepted as a catch-all.
7. Run an operator-approved outbound and inbound test, including spam-folder checks and SPF/DKIM/DMARC results, before selling the mailbox as live.

The prior `LightekEmailProvisioningService` address-allocation field was a placeholder, not an actual hosted mailbox. It is not silently converted to customer mailboxes. Provision real addresses in Mail Studio first. Corporate identity, passwords and Susu mailers keep their existing delivery configuration; `ApplicationMailer` now takes its sender from `MAIL_FROM` (default `no-reply@lightekmcg.com`) rather than `from@example.com`.

## Central SMTP configuration

New Mail Studio messages explicitly use Action Mailer's SMTP adapter, with:

- `LIGHTEK_MAIL_SMTP_HOST` (default `127.0.0.1`)
- `LIGHTEK_MAIL_SMTP_PORT` (default 25 for loopback, 587 otherwise)
- `LIGHTEK_MAIL_HOST` (default `mail.lightekmcg.com`, SMTP greeting domain)
- Optional `LIGHTEK_MAIL_SMTP_USERNAME` / `LIGHTEK_MAIL_SMTP_PASSWORD`

Loopback is intended for a trusted local MTA. Remote SMTP requires STARTTLS and certificate verification; ports and credentials must match that server's configuration. Configure local Postfix to trust loopback only for submission, reject unauthorized relay, sign both local and network-originated mail appropriately, and queue/retry internet delivery. Use an MTA message size limit of at least 20 MiB to allow a 10 MiB attachment/body message after MIME/base64 expansion. The inbound API and pipe accept raw messages up to 10 MiB.

Do not overwrite live Postfix, Exim, Dovecot, DKIM or Rspamd configuration without inspecting it. `audit_lightek_mail.sh` deliberately prints selected public routing settings, not passwords or message bodies. The next infrastructure patch should be based on that actual output. In particular, `mydestination`, virtual domains, relay domains and recipient maps interact; blindly replacing any of them can break existing inboxes or create a relay.

## SMTP → Action Mailbox ingress

After deploying the application, as root run:

```bash
cd /var/www/lightekmcg-site
python3 lib/scripts/prepare_lightek_mail_ingress.py
```

This prepares a private 256-bit ingress credential in the production environment file and `/etc/lightek/mail-ingress.json`. The pipe file is mode 0600 owned by the app user. The environment file is backed up under `/var/backups/lightek-mail`; backups are private. No SMTP routing is changed. Re-run the normal deploy to reload the environment in Passenger and Sidekiq before routing incoming mail.

A Postfix integration can use a dedicated pipe transport, run as the application user, with one envelope recipient per invocation:

```text
lightek_mail unix - n n - - pipe
  flags=Rq user=lightek argv=/usr/bin/python3 /var/www/lightekmcg-site/lib/scripts/lightek_mail_ingress.py --recipient ${recipient}
lightek_mail_destination_recipient_limit = 1
```

The first stanza belongs in `master.cf`; the destination-recipient-limit parameter belongs in `main.cf`. Preserve existing transports/maps. Export current verified/enabled addresses with `bin/rails lightek_mail:routes`. Exact recipient transport entries should map to `lightek_mail:`. Configure the correct local/virtual/relay recipient class and recipient maps based on the audit. Do not add a whole-domain catch-all or an open relay. `flags=R` supplies Return-Path for automatic-reply suppression; envelope recipients are sent separately from the untrusted To/Cc/Bcc headers.

The pipe sends raw MIME to `/api/lightek-mail/inbound`, with `X-Lightek-Mail-Ingress` and a JSON envelope-recipient header. It validates HTTPS certificates, refuses redirects, exits 75 on HTTP/auth/config/network errors so Postfix retains the queued message, and exits 65 for malformed or oversize input. An unrecognized recipient should already have been rejected at RCPT. The API does not trust arbitrary mail headers to pick a mailbox. Action Mailbox receives only after authenticated envelope ingestion. The endpoint routes and persists inbox records inside the intake transaction before returning HTTP 202; parsing/storage failures leave SMTP mail queued for retry. Outbound automatic-reply jobs enqueue only after that transaction commits, and the new routing branch leaves existing Nevaeh ingress in place for other mail.

Action Mailbox's raw-email lifecycle is separate from inbox retention. Inbox records retain the original source blob and decoded attachments. Retried MIME is deduplicated per mailbox. Trash is reversible; permanent deletion is offered only after moving a non-in-flight message to Trash. Back up the database, Active Storage files/object store, existing Vault keys and mail queue; mailbox storage is not a substitute for backups.

## HTTPS sending from client instances

Issue a key in a mailbox's **Connect an application over HTTPS** panel. It is shown once; the database stores its SHA-256 digest and a hint. Rotation invalidates the previous key. Store it in the client instance's Vault, not in browser JavaScript. HTTPS keys can only send from that mailbox, cannot read inbox bodies, and cannot impersonate another mailbox or use its templates.

```http
POST /api/lightek-mail/messages
Authorization: Bearer MAILBOX_KEY
Content-Type: application/json
Idempotency-Key: stable_application_request_123

{"to":"recipient@example.com","subject":"Your update","text":"Plain text","html":"<p>HTML alternative</p>"}
```

Alternatively provide an account-owned `template_id` and a `variables` object containing `name`, `email`, `company` or `subject`. Use a stable idempotency key when retrying a timed-out HTTP request. HTTP 202 is queue acceptance. Poll the returned status URL with the same key; it returns state, SMTP-acceptance timestamp and controlled error text, never body or secret material. API attachments are not supported in this first release; use Mail Studio for attachments. Disabled mailboxes and revoked feature access cannot submit through the API.

For client Rails instances using this same code, store `{"token":"MAILBOX_KEY"}` in Vault slug `lightek-mail-relay`, allow consumer `LightekMail::HttpsDelivery`, purpose `mail_submission`, and set `MAIL_DELIVERY_METHOD=lightek_https`. The optional `LIGHTEK_MAIL_RELAY_VAULT_SLUG` selects a different client secret. `LIGHTEK_MAIL_RELAY_URL` defaults to the central endpoint. The adapter enforces HTTPS/certificate verification and does not follow redirects. Sender addresses must match the key's mailbox. A different client app can use the HTTP contract directly instead of installing this Rails adapter.

## Templates, replies and delivery status

The email designer is separate from website CSS/layouts: it generates table-based email HTML with inline styling and a plain-text version. Heading, body, brand color, button and footer are editable, with optional custom HTML/text overrides and HTML/text exports. Custom HTML is sanitized; no Ruby/ERB is evaluated. Variables are allowlisted and escaped in HTML. Preview frames are sandboxed and CSP-block remote images/scripts. Preview uses sample values. Inbound HTML is sanitized too; attachments are downloaded only through an owner-scoped action, as downloads rather than inline executable content.

Mailbox templates are ownership-scoped and use optimistic locking to avoid overwriting another editor's save. Choose one for an acknowledgment or away reply. Automatic replies start disabled. The responder skips bounces, lists, bulk, auto-submitted mail, flagged spam, internal mailbox senders and no-reply senders; it requires explicit addressing and matching Return-Path/From. It permits at most one automatic response per sender/mailbox in 24 hours and still applies the mailbox quota. Configure trusted spam filtering at the MTA before enabling automation; this is not itself a spam-classification engine.

Delivery states are explicit: draft → queued → submitting → sent (SMTP accepted). A broken SMTP connection during submission may already have delivered DATA, so the job records `uncertain` and does not blindly resend. Inspect the MTA queue and delivery logs before composing another copy. Browser/API retries cannot create duplicate records when using a stable idempotency key. Run `lightek_mail:recover` through the existing scheduler to requeue records left queued during enqueue/worker failures and mark stale in-flight submissions uncertain. Recovery does not resend uncertain records. No new cron schedule is silently installed.

## Verification and launch

Run:

```bash
bin/rails test test/services/lightek_mail/mail_studio_test.rb test/integration/lightek_mail_test.rb
bin/rails lightek_mail:doctor
```

Doctor checks application counts, configured ingress and a TCP connection to the chosen SMTP server; it never sends a message and cannot establish deliverability. Development checks use actual Rails 8.0.4 models/controllers/Action Mailbox/Active Storage/Action Mailer, with a SQLite fixture app and local SMTP receiver. HTTP ownership/auth tests run in that fixture app; native account login, production PostgreSQL, live MTA configuration and external inbox delivery still need verification in the host environment.

Authoritative references:

- https://guides.rubyonrails.org/action_mailbox_basics.html
- https://guides.rubyonrails.org/action_mailer_basics.html
- https://techdocs.akamai.com/cloud-computing/docs/send-email
- https://www.postfix.org/SMTPD_ACCESS_README.html
- https://www.rfc-editor.org/rfc/rfc3834

## Activate webmail receiving on the central mail host

After deploying the receiving-workspace change, run on the host that has both
Postfix and the production application:

```bash
cd /var/www/lightekmcg-site
sudo bash lib/scripts/activate_lightek_mail_receiving.sh --apply --listen-public
```

If SMTP already listens on the required public interface, omit `--listen-public`.
The script checks both invalid-token rejection and real-token validation without
creating messages. It requires the previously prepared ingress credential to
match the environment loaded by Rails. Run `prepare_lightek_mail_ingress.py` and
reload the app if that prerequisite is missing. On a separate mail VM, use the same installer with `--remote` as described below.
It does not require Rails, Ruby or database credentials on that VM.

Activation backs up main.cf/master.cf, keeps existing transport maps, and puts an
exact-address map ahead of them. It leaves the default Dovecot transport intact
for other recipients, while new enabled Lightek deliveries go into webmail.
Existing Dovecot messages are retained and are not imported by this change.
A systemd timer synchronizes verified enabled recipients, domain entries and
exact inbox transports each minute. A newly created mailbox still needs to be
enabled and its domain verified. The sync refuses an empty export and preserves
existing domains; removing the last mailbox requires an intentional map cleanup.

This does not update DNS or firewall rules. Each hosted domain needs an MX record
pointing to `mail.lightekmcg.com` (or the configured mail hostname); the mail
hostname needs the server's public A record, and cloud/host firewalls must allow
inbound TCP 25. If migrating from an existing mail provider, preserve its mail
before changing MX. The dashboard's **Check receiving DNS** reports MX routing;
it does not claim an end-to-end SMTP test.

Verify with one external message addressed to an enabled mailbox. Confirm it
appears under **Inbox**, including attachments, then inspect `postqueue -p` and
`journalctl -u postfix --since '10 minutes ago'` if missing. HTTP/auth/network or
storage failures keep the message queued for retry. Receiving does not require
enabling global outbound sending.

### Local regression harness

`ruby test/support/lightek_mail_workspace_fixture.rb` runs the mail protocol and
workspace controller/view regressions with Rails 8.0.4 and SQLite. It uses a
fixture session and dashboard base controller; it does not validate native login,
private DymondDash engine integration, PostgreSQL locking or the live VPS.
Run `bash lib/scripts/verify_lightek_mail.sh` in the configured native application
for the host regression gate. The data migration `20261031190000` reconciles the legacy mail sending state during the normal deploy; it adds no tables or columns.
The sending policy model again uses the existing
`lightek_mail_sending_policies` singleton and database lock. Existing stored
sending settings are retained; the global `NilClass#sending_enabled?` workaround
is removed. If outgoing mail is paused in the persisted policy, use the existing
Mail administrator controls / `lightek_mail:resume` after checking that setting.

## Separate mail VM activation

Deploy the application first so the authenticated `GET /api/lightek-mail/routes`
endpoint is available. Copy the existing ingress JSON credential privately from
the application host to `/etc/lightek/mail-ingress.json` on the mail VM, mode
0600 owned by root. Do not generate a different token on the mail VM: its value
must match `LIGHTEK_MAIL_INGRESS_TOKEN` loaded by the central Rails application.
The JSON contains only `url` (the central HTTPS inbound endpoint) and `token`.

On the mail VM, update this repository checkout and run:

```bash
bash lib/scripts/activate_lightek_mail_receiving.sh --apply --remote --listen-public
```

Run as root. This installs the pipe/helpers under `/usr/local/lib/lightek-mail`,
creates an unprivileged `lightek` service account if needed, and places the pipe
credential at `/var/lib/lightek-mail/ingress.json` with mode 0600 in a directory
traversable only by root and the service group. The rest of `/etc/lightek`
remains private. The original source JSON stays in place for future rotations.
The installer checks the actual central ingress credential before changing mail
routes. It does not enable outbound sending or change DNS/firewall rules.

The timer fetches the receiving-eligible address allowlist over authenticated
HTTPS each minute. It refuses redirects, malformed or oversized exports and
empty results; failures leave existing SMTP maps intact. The remote VM never
needs the Rails environment file, database connection or a mailbox sending key.
The route-export endpoint accepts the ingress service credential only and sets
`Cache-Control: private, no-store`. A mailbox API key cannot enumerate routes.

### Preserving outgoing mail during this upgrade

The normal production deploy runs `db:migrate`. Reconciliation preserves an
already-enabled canonical policy and any canonical stop with a recorded reason.
Otherwise it copies the legacy `sending_policies.active` row, including a legacy
pause. If that table has no row, a previously SMTP-accepted outbound mail record
preserves the old model's working enabled default. A fresh installation with no
prior sending remains paused. The migration is idempotent and rollback never
changes operational mail settings. Customer suspensions and quotas are retained.

This handles the known code/data upgrade cases; it is not a substitute for
inspecting the actual production settings and testing receipt after activation.

### Conversation and HTML workspace

Reply and Reply all show the original message beside the composer on desktop,
with a collapsible original above the composer on mobile. The original is quoted
by default; the sender can omit it. Replies carry In-Reply-To and References
headers, and the reader groups up to 30 linked messages within the same mailbox.
Forwarding can optionally include the original attachments. Bcc recipients are
never copied into a reply or quoted header.

The composer supports rich formatting and a plain-text fallback. Outgoing mail
includes both HTML and text. Received HTML is sanitized and displayed in a
sandboxed frame; external images remain blocked until the reader explicitly
loads them for that message. No schema migration or mail-server configuration
change is required for this workspace update.

The isolated workspace fixture covers reply composition, drafts, mailbox
isolation, conversation history, forwarding, HTML sanitization and image opt-in.
Desktop and mobile browser checks use synthetic mail with that fixture; they do
not replace production authentication or SMTP delivery checks.

### Mail workspace navigation

The mail workspace separates the folder rail, message list, and reading pane.
Compose opens in a dock that can be minimized or expanded; folder changes,
searches, pagination and mailbox navigation retain the open composer. A reply's
From address stays visible when the active inbox changes. Save draft persists a
message on the server; closing or leaving an unsaved composer requires a warning.

Search supports quoted phrases and combinable `from:`, `to:`, `subject:`,
`is:unread`, `is:starred`, `has:attachment`, `after:YYYY-MM-DD` and
`before:YYYY-MM-DD` operators. Results paginate in groups of 40, within the
selected mailbox and folder. A fresh search searches All mail by default.

Select messages to archive, trash, move to inbox, star, or change read status.
Undo is available immediately afterward for ten minutes; it refuses to overwrite
a later change to the affected fields. All selected IDs must belong to the same
accessible mailbox or the entire action is rejected. Permanent deletion remains a
separate action in Trash. Supported image, PDF and text attachments can be
previewed in a sandbox; other file types download normally.

Outside text fields, `C` composes, `/` focuses search, `J`/`K` move between
messages, `R` replies, `X` selects the active message, and `?` opens shortcut help.
On smaller screens, the reader replaces the list and a Messages button returns
to it. Templates, auto replies, domain management, API keys and mailbox controls
are in Settings. No database migrations or SMTP changes are required.
