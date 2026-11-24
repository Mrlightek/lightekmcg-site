# Lightek MSP release handoff

## Gatekeeper provisioning preview

| Field | Pending request |
| --- | --- |
| Purpose | Isolated Lightek MSP acceptance for PRs #426, #432, #433 and #435 |
| DNS label | `batch-d-msp-r1.staging.lightekmcg.com` in a dedicated delegated staging zone |
| Owner | Synthetic `staging-msp@example.test` tenant on the staging control plane |
| Provider | Staging-only Akamai/Linode provider, North America, proposed Newark `us-east` |
| Compute | One Ubuntu 24.04 Linode 4 GB instance, proposed `g6-standard-2`, 2 vCPUs and 80 GB disk |
| Cost | $24 monthly plan cap. $0.036 per hour, about $1.73 for 48 hours of compute at published North America pricing. Confirm live catalog and applicable charges at approval |
| Expiry | 48 hours after the request is prepared, with scheduled Gatekeeper teardown |
| Secrets | Staging-only Vault owner, bootstrap, compute and DNS references. Synthetic database, Redis, storage and sandbox integrations |
| Network | Public TCP 80 and 443 for ACME and HTTPS. SSH from the controller IP only. TURN UDP 3479 and 50110–50159 and TCP 5350 from approved tester CIDRs. ClamAV TCP 3310 on loopback |
| Cleanup | Retire invitations and their accounts, delete the isolated compute resource through Gatekeeper and remove the matching staging A record. For rollback, provision a fresh instance pinned to a previously accepted release |
| Approval | Pending a live Gatekeeper record. Requires the isolated control-plane address or existing request ID and scoped operator access |

Published pricing is available from [Akamai North America pricing](https://www.akamai.com/cloud/pricing/north-america). Before approval, import the isolated candidate from the approved control plane with `script/lightek/release_assurance_import.rb` or use Dashboard assembly and publication. Select the reviewed `main` revision as an additional candidate source to carry forward its production schema and lockfile. Use Release Assurance to prepare the priced Gatekeeper request and capture its ID. Approve provisioning in Gatekeeper and deploy the pinned revision from Release Assurance.

## Private dependency CI

Install the GitHub App identified by the CI App ID and key on the `lightekmcg` account. Grant repository **Contents: Read** and **Metadata: Read**, with the installation limited to:

`dymond_bank`, `dymond_booking`, `dymond_catalog`, `dymond_compute`, `dymond_dash`, `dymond_dispatch`, `dymond_kb`, `dymond_site`, `dymond_studio`, `dymond_theme`, `lightek_kernel`, `lightek_ui`, and `marlon`.

The Actions repository needs the matching `LIGHTEK_CI_APP_ID` variable or secret and the `LIGHTEK_CI_APP_PRIVATE_KEY` secret. The failing workflow reaches token creation and gets a 404 for the installation lookup. Check the installed App identity and repository selection before retrying. Details are in the [GitHub App installation documentation](https://docs.github.com/en/rest/apps/installations).

## Tester invitation drafts

Send after the staging revision, the assigned test and the invitation expiry have been confirmed. Create an individual one-time code in Dashboard for each consenting tester. Share that code through an approved private channel.

> Hi [first name], I’m inviting you to test Lightek’s managed IT services on [Windows/macOS/Linux]. Please use the disposable test environment we provide or an approved VM and use only synthetic accounts and files. Open [beta portal], enter the one-time code I send separately, and follow the assigned scenario. Your access ends [date, time and time zone]. Report the result and any redacted screenshots in the portal. Let me know if you need to stop or have your access revoked.

| Platform | Guided acceptance | What to capture |
| --- | --- | --- |
| Windows | On a snapshotted Windows VM, enroll the synthetic endpoint, authorize one eligible native update, confirm the installed version and compare it with the Gatekeeper receipt. In a separate attended support session, test capture and revoke consent. Test native input and unattended access once Batch D makes those controls available. | Build and update identifier, gate and completion receipt, before/after access states, redacted screenshot |
| macOS | On an authorized disposable Mac or VM with a graphical login, verify the selected native update and installed build. Confirm Screen Recording consent and session ending. Exercise input and unattended access after Batch D supplies those controls and their authorization flows. | OS build, signed-in desktop profile, consent and revocation receipts, redacted screenshot |
| Linux | Use a disposable Ubuntu VM and a synthetic backup. Verify separate target identity, restore cutover and readback, then rehearse rollback. In Dashboard, verify consent, relay-backed video, recording playback, and rejection of the harmless scanner test fixture. | Backup ID and digest, before/after verification, relay protocol and consent transitions, redacted release or scan receipt |
| Commerce and browser | Use synthetic customer and technician accounts to complete booking, invoicing, and sandbox payment and payout. Verify cross-account denial and that receipts refer to the expected candidate. | Booking and sandbox reference IDs, result, affected role, redacted screenshot |

Mark absent controls and skipped steps **Blocked**. Keep simulated and hosted tests separate from human desktop evidence. After retesting, offboard participants and revoke staging access.
