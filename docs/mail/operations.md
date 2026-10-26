# Lightek Mail: central delivery, webmail and email templates

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

The pipe sends raw MIME to `/api/lightek-mail/inbound`, with `X-Lightek-Mail-Ingress` and a JSON envelope-recipient header. It validates HTTPS certificates, refuses redirects, exits 75 on HTTP/auth/config/network errors so Postfix retains the queued message, and exits 65 for malformed or oversize input. An unrecognized recipient should already have been rejected at RCPT. The API does not trust arbitrary mail headers to pick a mailbox. Action Mailbox receives only after authenticated envelope ingestion, and the new routing branch leaves existing Nevaeh ingress in place for other mail.

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
