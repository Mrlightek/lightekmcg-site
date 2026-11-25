# Batch D isolated staging

Use a dedicated Ubuntu native Rails installation and a separate disposable desktop runner. Run only with synthetic test identities, cases and attachments. The scripts require a Batch D-prefixed hostname and verify the requested deployed revision before changing services. Do not reuse production integrations, customer credentials, payments, mail routing or enrolled customer devices.

## Provision through Gatekeeper

1. Prepare a clean reviewed staging checkout with Batch B, C and D together. The native website deployment packages that checkout. Building only the Batch D branch omits Batch B's request tables if Batch B is still unmerged. Record the exact SHA of the combined checkout.
2. Use the Dashboard's existing Compute/ProvisioningRequest flow with a dedicated test owner, an Ubuntu request, and a node label equal to the first component of a hostname such as `batch-d-qa.staging.example.org`. Register its website config with `bin/lightek-deploy register --request-id …`, using the existing `Gatekeeper::WebsiteDeployment` Vault policy. Use a staging-only Vault secret. Gatekeeper's existing provider approval and DNS preflight remain in force.
3. Preview from the authorized Rails control plane with the staging checkout as the packaging source. The wrapper returns the provider, region, plan, and source revision. Then set `LIGHTEK_BATCH_D_PROVISION=1` to execute the same command with the approved budget and request. If allocation is interrupted, use Gatekeeper's existing reconciliation against the created staging node rather than allocating a second node.

```sh
bin/rails runner deploy/it-support-staging/provision.rb -- ACTOR_ID REQUEST_ID STAGING_HOST STAGING_SHA
```

This requires an authorized Gatekeeper operator who can invoke the website deployer and the staging request's scoped server bootstrap and DNS Vault entries. The application checkout and database are separate from production. The native deployer verifies HTTPS, owner sign-in and the release receipt. Its dependency installer needs access to the existing private application dependencies.

## Enable the staging services

On that dedicated host, run the script from the deployed checkout. Without the environment flag it checks the managed installation, active vhost, certificate and live release. With the flag it installs and configures the packages, generates a staging-only TURN secret, and updates this instance's Rails encrypted credentials. Re-run after a new release or certificate renewal to refresh the local credential and certificate files.

```sh
sudo /opt/lightek-sites/STAGING_HOST/current/deploy/it-support-staging/services.sh STAGING_HOST STAGING_SHA
sudo env LIGHTEK_BATCH_D_APPLY=1 /opt/lightek-sites/STAGING_HOST/current/deploy/it-support-staging/services.sh STAGING_HOST STAGING_SHA
```

Allow UDP 3479 and 50110–50159 and TCP 5350 on the staging provider firewall for the authorized test networks. Preserve HTTPS certificate validation. ClamAV listens on 127.0.0.1:3310 on the Rails and Sidekiq host. The installer leaves a harmless test signature on this staging scanner and keeps the vendor signature updater enabled.

The existing managed LiveKit media installer serves conferencing rooms. Batch D currently uses peer-to-peer signaling and the TURN REST shared-secret format from `ItServices::RemoteScreenIce`. The separate coturn service uses different ports from LiveKit and preserves the existing conferencing configuration.

## Automated checks

Run the checked-in `batch-d-acceptance.yml` on an isolated Actions run. Linux launches a real Xvfb desktop, real Chromium display capture, a loopback-only coturn relay, and an isolated ClamAV daemon. The browser requires an actual decoded video frame on the receiving peer and relay candidates on both ends. The scanner probe runs the application adapter against both a clean file and the harmless signature. The Windows and macOS jobs exercise Chromium WebM recording and playback of synthetic canvas frames.

For deployed staging, produce a short-lived ICE bundle using the Gatekeeper instance launcher. Use a private file and copy it only to the disposable test runner. The Playwright setup follows the repository's existing conferencing acceptance version.

```sh
# On the isolated native staging host, as its app user:
cd /opt/lightek-sites/STAGING_HOST
umask 077
python3 run-app.py bin/rails runner deploy/it-support-staging/clamav_probe.rb
python3 run-app.py bin/rails runner deploy/it-support-staging/turn_probe_credentials.rb > "$HOME/batch-d-ice.json"

# On a disposable Linux desktop runner with Node 22, Xvfb and xauth:
npm install --no-save --package-lock=false playwright@1.62.1
npx playwright install --with-deps chromium
deploy/it-support-staging/run_desktop_probe.sh PATH_TO_PRIVATE_ICE_BUNDLE
```

The bundle expires after five minutes. Run the external probe from the intended staging client network and remove the bundle once checked. The probe tests both UDP TURN and TLS TURN when supplied and verifies Chromium selected a relay. It tests transport and native desktop capture independently of Lightek's customer and technician UI.

## Desktop acceptance still required

| Platform | Hosted coverage | Interactive staging coverage |
| --- | --- | --- |
| Linux | Real capture on a disposable Xvfb monitor, forced UDP relay, decoded frame, real ClamAV adapter | Dashboard role and consent flow, recording/playback, deployed UDP/TLS relay, separate real X11 or Wayland sessions for host permissions and input |
| Windows | Chromium WebM codecs and Batch B's Python/PowerShell and native update interface checks | A logged-in disposable Windows VM with a technician browser on a second client. Verify real capture picker, native keyboard and mouse, revocation, termination and unattended lifecycle after implementation |
| macOS | Chromium WebM codecs and Batch B's Python and OS build checks | An authorized disposable macOS desktop with a usable GUI login and explicit Screen Recording / Accessibility permissions as required by the eventual endpoint implementation. Verify real capture, input, revocation and unattended lifecycle |

An Actions browser codec result does not establish native support for the platform. The current Batch D stage can exercise attended viewing, recording, file transfer and consent revocation. Native input and unattended access still require their Batch D implementation and interactive acceptance. Use synthetic test cases for the complete Dashboard flow, and retain only redacted release, relay and scan evidence.

## Gatekeeper approval and external beta

The Batch E provisioning bootstrap owns preparation, capacity quote validation and authorization. After it is installed, the following wrapper reports a matching request or prepares a pending one through the same Gatekeeper service as the Dashboard:

```sh
bin/rails runner deploy/it-support-staging/request.rb -- inspect ACTOR_ID batch-d-msp-r1.staging.lightekmcg.com
bin/rails runner deploy/it-support-staging/request.rb -- prepare ACTOR_ID batch-d-msp-r1.staging.lightekmcg.com
```

Review one Ubuntu 24.04 `g6-standard-2` node in the configured staging region with the synthetic staging owner, a 2,400-cent monthly cap, and a 48-hour lifetime. The provider quote is recorded on the request. Authorization must bind the approved request to the reviewed release candidate. Keep access to HTTPS 443 for testers, HTTP 80 for the existing certificate challenge, SSH 22 for the deployment worker only, and TURN UDP 3479 and 50110–50159 and TCP 5350 for acceptance. ClamAV TCP 3310 and data services stay local/private. Use the configured staging Vault bindings for compute, DNS, and website ownership. Keep the release's dedicated worker and separate state.

If acceptance fails, stop the staging test sessions and revoke tester access and device tokens. Retire the environment through Release Assurance, verify the dedicated node and delegated DNS entry were removed, and retain redacted operation and test receipts. Release Assurance's expiry workflow covers the same isolated resources. Leave unrelated instances and DNS entries intact.

The beta starts with a Release Assurance invitation and its temporary staging account. From the client Dashboard, open **MSP beta test checklist** for the downloadable one-shot check-in and guided tests. Batch B and D use the same Gatekeeper device record for that staging account. The technician uses the staging Remote support workspace and the existing IT Service Request assignment to match each test device. The Dashboard shows check-in and session receipts without exposing raw diagnostics. Feedback goes to Nevaeh as a technical support case. The check-in package sends only the consented system percentages and executes no maintenance. Native maintenance uses the existing Batch B procedures with per-operation approval on a disposable endpoint.
