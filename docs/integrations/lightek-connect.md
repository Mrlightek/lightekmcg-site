# Lightek Connect

Lightek Connect adds an agency workspace to WordPress and an embedded app to Shopify. Both use the same Rails API, Dashboard navigation, agency hierarchy, Gatekeeper provisioning, and client-instance connection. Client sign-in remains unchanged.

## Delivered behavior

- Agency creates a platform-bound, ten-minute, single-use connection code in **Dashboard → Lightek Connect**.
- WordPress stores the resulting credential encrypted, per administrator. Browser JavaScript never receives that credential.
- Shopify verifies a fresh App Bridge ID token for each request and binds the Lightek connection to both shop and staff member. Connecting one staff member does not authorize other staff members.
- Both interfaces show client websites and recent application deployments. Navigation is derived from the actual permission-filtered Dashboard defaults, rather than a separate list of modules.
- Full tools open through a browser-verified MFA handoff. The initial link allows ten minutes to sign in or enroll an authenticator at the central origin; after approval, redemption is single-use and expires in sixty seconds. This first version uses a top-level Dashboard tab for full workflows; it does not reproduce every Dashboard form inside WordPress or Shopify.
- Website rename is available directly in the connector. For a federated client, Rails calls that client's actual HTTPS instance, checks current agency authority, saves there, and validates the returned hostname/name. The central ledger is not substituted for a remote save.
- Existing hosting purchases and payment-confirmed provisioning remain the route to a new client server. The connectors do not allocate a free server or bypass infrastructure entitlements.
- Revocation disables connection credentials and pending grants. Delegated client sessions expire after one hour and check central authorization on each request; network failures deny access. Client sessions created through normal login are unaffected.
- Remote management runs under the client's local owner permissions, attributed to the originating agency connection. It never creates a super-admin on the destination instance.

## Deployment and installation

1. Deploy this application revision and run `bin/rails db:migrate` centrally and on managed client instances using the existing fleet update workflow. Remote management/edit endpoints require the new revision on both ends.
2. Paid native/container installations already receive their peer configuration through the existing provisioning pipeline. Existing installations need a working, active reservation-federation connection, or need that existing connection workflow applied first. No additional plaintext credential or shared master signing key is introduced.
3. Set `LIGHTEK_RESERVATION_ORIGIN` to the canonical central HTTPS origin if different from `https://lightekmcg.com`. Client websites must resolve to public addresses with valid TLS certificates.
4. Run `python3 script/package_lightek_connect.py`. Upload `tmp/lightek-connect-wordpress.zip` to WordPress and activate it. Each administrator opens **Lightek**, then enters their WordPress connection code.
5. Register the Shopify app. Open **Dashboard → Lightek Connect → Shopify app credentials** as a super admin and save the Client ID and Client secret. Both are encrypted in Vault under `shopify-connect`; the secret is never redisplayed. The connector checks out that entry at runtime with consumer `LightekConnect::ShopifyCredentials` and purpose `shopify_connect`. No Shopify credential environment variables or application restart are needed. Missing, disabled, expired, access-denied or undecryptable Vault credentials fail closed; there is no environment fallback. Fill `integrations/shopify/shopify.app.toml.example` with the actual application URL and client ID and configure managed installation. The app requires no Shopify customer/order data scopes and makes no Shopify Admin API calls.
6. Install on a development shop, open the embedded app, and enter a Shopify connection code. Every staff member who needs access pairs their own Lightek identity.

`integrations/wordpress/.../assets` is generated from `public/lightek-connect`, so both clients ship the same UI. Re-run packaging after shared UI changes. Do not load remote plugin scripts into WordPress.

## Acceptance walkthrough

1. Sign in as an agency with an active hosting allowance. Connect its WordPress administrator or Shopify staff member.
2. Open the hosting workspace using its navigation action. Create/select the client and purchase an eligible package through the existing checkout. This step uses the full Dashboard handoff in this release.
3. Confirm payment and the provisioning job succeed; refresh Connect to see the ready launch.
4. Select **Manage client instance**, then confirm the handoff. Verify the destination is the client's hostname and its full Dashboard opens.
5. Save a website name directly in Connect. Reload the destination website settings independently and verify that name. For federated sites, the connector only reports success after the destination confirms it.
6. Revoke the connection centrally. Confirm the plugin can no longer save and the delegated client session is rejected on its next request. Verify normal client login still works.
7. Repeat with an unrelated agency, a reassigned client, expired/replayed codes, and a second Shopify staff member. All unauthorized access must fail.

## Submission and commercial gates

These are development integrations, not approved marketplace listings. No platform registration, submission, live billing change, or production deployment is performed by this commit.

- WordPress: publish actual service terms/privacy URLs and put those exact links in the plugin readme; supply listing metadata and test against the submission target WordPress/PHP versions. The external service is disclosed; no WordPress customer/order synchronization is implemented.
- Shopify: complete public-distribution registration, configuration, development-store acceptance and review. The shared Dashboard currently includes external commerce workflows. Before distributing commercially, implement Shopify-supported app billing or obtain Shopify's explicit approval for the applicable external-service billing arrangement. Do not submit or market this build as billing-compliant or route Shopify app charges to external checkout without that resolution.
- Live paid provisioning, real WordPress/Shopify installation, and cross-server acceptance require deployed accounts/instances. Isolated tests do not establish those outcomes.

## Extending and updating

Backend modules added to Dashboard navigation become visible to both connectors, subject to the existing account permissions. A new native connector interaction still needs a UI update; it does not duplicate business logic. Apple/Google/mobile/OTT deployment services should be implemented centrally with that same account/client authorization. This change does not implement those future deployment providers.

Connector release workflow: change shared UI/API → run checks → bump connector version if its bundle changes → package WordPress assets → test supported WordPress and a Shopify development shop → review API compatibility → submit/release through each platform. Update client fleet instances before advertising newly required remote capabilities. Keep older API versions supported during connector review windows.

## Verification

- `ruby test/standalone/lightek_connect_api_test.rb`: real Active Record migrations/models and Action Controller HTTP tests, with private engine boundaries replaced by minimal fixtures. Includes hierarchy authorization, connection/grant expiry/replay, revocation, local persistence, remote-authority boundary, JWT validation, webhook signatures, and private-address exclusions.
- `php test/standalone/lightek_connect_wordpress_test.php`: executes the plugin against WordPress API boundaries; verifies permissions/nonces, credential encryption, per-user isolation, fixed upstream, no redirects and disconnect behavior.
- `NODE_PATH=/path/to/jsdom/node_modules node test/standalone/lightek_connect_ui_test.cjs`: shared UI pairing, text-safe rendering, save feedback, authenticated requests, and handoff for both platforms.

Tests do not load the full private engine dependency stack or contact payment, hosting or platform services. The GitHub workflow runs these checks independently of the existing Rails suite.

## Disposable WordPress testing from Dashboard

After deployment and both migrations, super admins can open **Dashboard → Lightek Connect → Disposable WordPress test environment**, select a managed server, and click **Create WordPress test environment**. The selected server must already have Docker Compose, Apache, and Certbot, at least 384 MB available memory and 3 GB free disk. Existing deployment/native-update scripts install a root-owned helper and its scoped sudo rule automatically. The web account does not execute a mutable checkout script as root for this operation.

A generated `wp-test-<random-key>.lightekmcg.com` hostname is used. Set `LIGHTEK_CONNECT_TEST_ZONE` to another configured GoDaddy zone if needed. Setup creates its own DNS record, bounded WordPress/MariaDB Compose project, local-only backend port, HTTPS virtual host, certificate, WordPress administrator, and installed/activated Connect plugin. Secrets are generated and encrypted in Vault. **Show test login** retrieves only the WordPress administrator credentials for the super admin over a non-cacheable response; the Vault access is audited. The public installer is never exposed before WordPress bootstrap completes.

When ready, open the test WordPress admin, sign in, open Lightek, and paste a WordPress connection code. This environment hosts WordPress only; the Lightek API still runs at its configured central origin. The resource checks are prerequisites, not a guarantee that existing production workloads have spare capacity.

After testing, type the exact sandbox hostname and select **Delete test environment**. Cleanup removes only its marked virtual host, Compose containers/volumes, dedicated certificate and unchanged recorded DNS record, then disables its Vault credential. It does not delete the server or prune shared images. The status/history row remains. Changed resource ownership stops cleanup for review. Interrupted jobs can be cleaned up after 40 minutes, beyond the remote execution timeout. Failed installs expose the same cleanup action.

This implementation has isolated lifecycle/ownership tests. No real server has been provisioned or deleted by this change; live WordPress installation and authentication remain acceptance work.

## Shopify development store: first steps

1. Open https://dev.shopify.com/ and sign in or create your Shopify developer/Partner organization.
2. Select **Stores → Create store → Dev**. Create a test store named **Lightek Connect Test** (or an available variation), choose a development plan, and complete creation. Use a dev store rather than a live merchant trial.
3. Open that store's admin and record its `myshopify.com` hostname. This is not a secret.
4. Next, register/link **Lightek Connect** to the organization and its configuration using Shopify CLI for the eventual App Store workflow. The app URL is `https://lightekmcg.com/connect/shopify` after this revision is deployed. Preserve the existing Rails backend rather than replacing it with a new generated backend.
5. Save the Client ID and Client secret through **Dashboard → Lightek Connect → Shopify app credentials**; do not paste the secret into chat or commit it. Install the development app, then connect a Shopify-specific agency code.

Official references: https://shopify.dev/docs/apps/build/stores/development-stores and https://shopify.dev/docs/apps/build/dev-dashboard/create-apps-using-dev-dashboard. Public distribution and commercial billing approval remain separate from development-store testing.

## Shopify credentials in Vault

The Shopify setup form is available only to the platform super admin. It saves an encrypted `credential` entry named `shopify-connect`, provider `shopify`, purpose `shopify_connect`, with structured fields `client_id` and `client_secret`. Its policy allows only consumer `LightekConnect::ShopifyCredentials` and purpose `shopify_connect`. The existing Vault screen can also create this exact entry using structured fields and those policy values.

The embedded app reads its public Client ID from that entry. Session-token and webhook signature checks use the same Vault credential, with audited checkouts and no persistent plaintext cache. Disabling the Vault entry stops Shopify authentication. Saving a replacement takes effect on the next request. Existing Shopify credential environment variables are ignored and are no longer part of setup.

Validation additionally exercises the real Vault migration/models, encryption, policy and audit services, with only the external master-key source isolated. Tests cover encrypted storage, missing/disabled/expired/access-denied/corrupt credentials, immediate rotation, checkout cleanup, privileged Dashboard saves, secret non-disclosure, and CSRF rejection.

## Verified agency MFA handoff

1. Open a Dashboard or client-management link from WordPress or Shopify. Both start at the central Lightek origin. A connector bearer token, Shopify staff session or browser-supplied MFA field cannot approve the link.
2. Continue with the **same agency account that owns the connection**. Sign in and verify its Lightek authenticator when needed. Existing direct Lightek sessions can supply their verified MFA within the normal twelve-hour MFA window. When opening a client from a locally delegated agency Dashboard, Lightek reuses that original direct source after revalidating the current grant, instead of requesting MFA again; an unverified delegation cannot supply a source. Enrollment keeps the handoff return link after recovery codes are shown.
3. Lightek binds the approved grant to that persisted source session, connection and exact client site. Client-instance links then show the existing confirmation form on the client's HTTPS origin. GET never consumes a grant; the confirmation POST requires CSRF protection.
4. Delegated sessions last at most one hour, bounded by the original MFA expiry. Each protected request rechecks the source session, factor, SSO status/membership (when applicable), agency role, connection revocation, client relationship and company policy. Remote requests use the existing Vault-backed, site-bound federation bearer channel. No client-owner MFA timestamp is created, and no client authenticator secret or recovery code is shared.
5. Existing authorization still decides which records and actions are available. Central Dashboard handoffs retain the agency actor; a remote handoff retains the existing client-owner account scope, with the source agency and grant attributed in Connect audit events. This change does not add new connector permissions or create a super-admin on the client.

**Client policy:** Dashboard → Directory & Access → Company MFA policy → **Accept verified agency MFA through Lightek Connect**. Acceptance defaults on, with verified agency MFA mandatory for every handoff regardless of the company-wide MFA checkbox. Turning acceptance off requires direct sign-in and invalidates existing handoffs on their next request. The source agency's policy also applies. Authenticator changes, SSO linking, directory/access-policy mutations and legal-provider credential changes still require direct sign-in and existing password checks. Finance, People, directory viewing and compliance monitoring use verified delegated MFA plus their existing permissions.

**Deployment:** run `20261113230000_add_connect_mfa_handoff` centrally and on client instances, and update both applications through the existing fleet pipeline. Legacy/unverified delegated sessions and old servers without the verified response fail closed; relaunch Connect after updating. If the issuer is unavailable, delegated requests are rejected, rather than falling back to a client-owner sign-in challenge. Normal direct client sign-in remains available.

**Acceptance:** `ruby test/standalone/enterprise_connect_mfa_checks.rb` runs real Rails HTTP sign-in, authenticator enrollment/step-up, source session/grant storage, both management controllers, peer bearer authentication, sensitive views and audit assertions. The in-process cross-server transport is replaced for deterministic testing. Run a real agency → client check on the deployed central/client revisions before claiming live acceptance.
