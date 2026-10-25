# Lightek Marketplace 8.9.2

Products have editable groups and monthly, yearly, both, one-time or free billing.
The editor uses real Rails requests for Details, Pricing, Delivery and Review. It
renders one step at a time and preserves entered values through Back and Continue.
Moving between steps creates no products, plans or billing records. The small
optional JavaScript asset updates relevant fields and preview text; no Stimulus
controller or JavaScript is needed to finish the editor. Without JavaScript, use
Apply billing options or Apply delivery method after changing those selectors.

Manage product groups at /dashboard/marketplace/groups. Group names, descriptions,
order and availability are editable. Existing products keep their group keys when
names change. Groups that are used by any product cannot be archived until those
products are moved. Four original groups and any existing custom group keys are
preserved by the migration. No demo products or prices are created.

Monthly and yearly are prices on one product and one dedicated subscription plan.
Customers choose their billing period on the product detail page and Bank checkout
receives that same interval. Saving new product prices creates a new billing version;
existing subscriptions retain their original plans. Trials and setup fees are
checked against Bank's actual preview calculations before a product version is saved.
USD remains the editor currency.

Delivery choices are customer website, team-delivered work, or application access.
Application access uses only connections explicitly configured under
/dashboard/marketplace/connections. A connection explains what customers get and
where they open the application. Its application access key must identify a real,
active feature. Administrative features cannot be sold. Marking a connection ready
records the super admin and review time and verifies that the entry path is a local
application route. This is an operator review, not an automated proof that the
application uses that key correctly. Verify access using a client account before
marking it ready. Internal features are never automatically imported into the chooser.
Legacy 8.8 purchase fulfillment remains supported without importing those features.
New purchases pin the reviewed connection key and destination in their billing version.
Unready or changed connections block new access delivery rather than granting another
feature silently. Existing manual access and subscription pricing stay unchanged.

Website delivery creates site records for the actual purchasing customer. DNS, TLS
and server activation are unfinished. Website orders stay in provisioning after
record creation; that stage does not establish a reachable website. Team delivery
creates one related work request; application delivery grants the configured access.
A purchase lock and saved receipt prevent repeated notifications from repeating work.
Cancellation revokes only the purchase-owned grant, preserving manual or other valid
purchase access. Renewal, past-due and refunds still use the existing Bank policies.
Welcome/instruction text is recorded with delivery, not emailed by this editor.

8.9.2 collects the first selected monthly/yearly period and setup fee on one Bank
invoice. Trials defer recurring charges. New subscriptions with money due start
unpaid. The complete invoice must be paid before activation and delivery; partial
or wrong-currency settlements cannot mark the order paid. Cancellation does not
revive a canceled order or subscription when a late payment arrives. A dispatch
outage preserves the committed order rather than inviting a second purchase.
Unmanaged offers continue through the original Bank checkout. Existing invoices
and orders are not rewritten. Processor webhook signature verification remains
owned by Bank; the new regression tests exercise its supplied settlement services
without sending processor requests. Staging processor acceptance is still required.

The upgrade adds product-group and application-connection tables. It does not change
existing listing configuration columns or delete existing records. Stop the local
Rails server before installation, run the installer, then restart Rails and Sidekiq.
CHECK_ONLY=1 checks the intended update without source or database writes. Backups and
installed hashes remain under tmp/lightek_marketplace_v8_7/. Only the dedicated new
migration is run in development and test. The installer then runs autoloading and the
host acceptance suite and captures the existing website/deployment source plus a
limited node inventory in tmp/marketplace_website_handoff/. No charges, external provider calls, commit, push or deployment
are performed by installation. The local build was checked with Rails 8.0.5.1,
fixture Bank models and real browser requests; host tests use actual private gems and
PostgreSQL. These checks do not establish live payment-processor acceptance.
