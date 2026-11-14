# Agency demos and paid upgrades

Superadmins and agencies open **Client demos** in Dashboard. Choose the agency, demo duration (default 14 days, 1–90 allowed), maximum active demos, and a published full-instance product linked to a subscription plan. Create a new client by email or select an existing direct client without other websites or bookkeeping accounts. A demo is an isolated website workspace on the current application instance; it does not allocate a cloud server or grant server-administration privileges.

## Public requests

Select the agency’s own public website and enable public requests. Link its **/request-demo** URL from your website’s Request demo button. Requests send an email confirmation valid for 24 hours. Opening the link shows a confirmation page; submitting it creates the workspace and starts its expiry clock. New clients set a password through the existing onboarding flow and enroll in MFA. Existing accounts must sign in and must already belong to the agency; requests cannot transfer account ownership. Capacity and request throttles prevent unbounded allocations. Public requests are disabled by default.

## Upgrade and cleanup

The demo client selects **Upgrade to my own instance**, reviews the hosted payment checkout, and pays. Verified payment triggers the existing paid-instance provisioning pipeline. The checkout freezes website pages, standard sections and built-in design settings, up to 100 pages, 100 sections per page and 2 MB. Custom Studio sections/designs require conversion to built-in sections before checkout. Uploaded media, custom integrations, financial history, users and credentials are not migrated. Avoid relying on temporary demo media URLs in copied content.

The new instance installs the snapshot before passing the existing readiness verifier. Native and Docker installations support the snapshot; rebuild application images with this release before using Docker demo upgrades. An old image fails safely rather than completing an incomplete migration. Repeated installation retries preserve subsequent owner edits.

After verified readiness, a worker deletes the original temporary website and its owned site-scoped records and attachments. A paid upgrade that is still provisioning holds the source workspace for review. The client’s central billing/login identity remains for service access. Live store checkout, outbound marketing and live payroll payouts are blocked on demos.

At expiry, site access stops immediately. A scheduled cleanup removes the workspace; a five-minute Sidekiq sweep recovers missed cleanup jobs. Empty accounts created only for an expired demo are removed when they have no real business resources. Existing client identities, paid orders, shared resources and unrelated sites are retained. Settled commerce records or changed ownership stop destructive cleanup and show **Needs review** to the agency. Data outside website ownership may retain the identity and require operator review.

## Deployment

Run normal Rails migrations on central/agency instances and update their workers. Deploy the same release to paid-instance installers/images. Keep Sidekiq and its schedule active. This release adds one migration; configuration is per agency and public requests remain off until configured. No paid resources or demo deletions occur merely from deploying it.

## Acceptance

Run `ruby test/standalone/agency_demo_checks.rb` with the public Rails acceptance dependencies and `PEOPLE_DATABASE_URL` configured. The enterprise acceptance workflow runs the onboarding suite plus demo ownership, confirmation/CSRF, expiry, content-copy idempotency, payment/readiness and cleanup checks. Run `python3 -m unittest test.scripts.test_paid_instance_verification` and `ruby test/standalone/website_deployment_dispatch_test.rb` for installer dispatch.
