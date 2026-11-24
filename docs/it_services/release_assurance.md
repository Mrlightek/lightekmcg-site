# Lightek Release Assurance

Open **Release Assurance** under Operations or from **Servers & Applications**. The workspace uses a dedicated control plane with its own PostgreSQL, Redis, Git write identity and staging Vault. A super administrator owns each release candidate and its beta roster. Apply the Batch E migrations before enabling the workspace.

## Staging control plane

Configure the web process and a Sidekiq worker that consumes the `release_assurance` queue. The existing Gatekeeper deletion worker on `default` must run as well. The deployment worker needs Ruby 3.3.6, the candidate's private gems installed for its exact lockfile, Git 2.38 or newer, an existing Gatekeeper control node, and Chromium with Playwright available to Node. Use the same browser package version as Batch D. The browser probe reads the staging revision and a public synthetic page, captures the homepage, and checks that the staging sign-in form loads.

| Setting | Value |
| --- | --- |
| `LIGHTEK_RELEASE_ASSURANCE_RUNNER` | `1` on the isolated control plane |
| `LIGHTEK_RELEASE_ASSURANCE_ZONE` | A separately managed, delegated `staging.example.org` zone in the existing GoDaddy configuration |
| `LIGHTEK_RELEASE_ASSURANCE_TEST_NETWORKS` | Comma-separated approved IPv4 CIDRs for TURN clients and probe runners |
| `LIGHTEK_RELEASE_ASSURANCE_OWNER` | Synthetic owner, for example `staging-msp@example.test` |
| Staging provider | Active and healthy `linode-staging` record with the built-in Linode adapter |
| `LIGHTEK_RELEASE_ASSURANCE_REGION` | Region for the staging quote. MSP uses `g6-standard-2` |
| `LIGHTEK_RELEASE_ASSURANCE_DNS_VAULT` | Staging DNS reference. The execution worker must use this same slug as `GODADDY_VAULT_SLUG` |
| `LIGHTEK_RELEASE_ASSURANCE_CERTIFICATE_EMAIL` | Approved certificate contact |
| `LIGHTEK_RELEASE_ASSURANCE_OWNER_VAULT` | A staging-prefixed Vault entry authorized for Gatekeeper WebsiteDeployment and its `website_deploy` purpose |
| `LIGHTEK_RELEASE_ASSURANCE_ACTIONS_TOKEN` | Optional read-only Actions access for CI evidence lookup |

Use separate staging-scoped provider and DNS credentials. Grant Git write access for the runner's `release-candidates/**` publication refs and apply repository rules restricting those refs to that identity. Keep it out of branch-protection bypass lists and production deployment permissions. Review all source and Actions changes before publishing any revision. The existing CI workflow uses the repository's established private dependency access.

## Combined MSP acceptance

1. Assemble the **Combined MSP** profile. It pins `develop` and PRs #426, #432 and #433 at assembly time. Add the Batch E PR in Sources if Batch E has not yet reached `develop`. Review every listed source and workflow change. The candidate also adds a push trigger to the three existing MSP acceptance workflows so they run against the exact candidate SHA. Publication triggers CI and preflight on the candidate ref.
2. Follow the [standalone provisioning bootstrap](msp_provisioning_bootstrap.md) to prepare and approve the request on the existing Dashboard before the combined candidate is deployed. Prepare a new Gatekeeper request or enter the ID of a fresh dedicated request previously configured for this hostname. Use a unique `batch-d-*.staging.example.org` hostname. Review the catalog estimate, spending cap and expiry. Grant explicit approval in the existing provisioning Dashboard, then approve deployment of the pinned candidate in Release Assurance.
3. Gatekeeper checks live pricing, DNS and pinned dependencies before allocating a server. The native installer configures TLS and a fresh PostgreSQL, Redis and Sidekiq installation. The staging host job applies its firewall and reuses Batch D's TURN and ClamAV installer. HTTP and HTTPS serve ACME and the staging app. SSH is scoped to the deployment peer. TURN uses UDP 3479 and 50110–50159 and TCP 5350 for approved test networks. ClamAV remains loopback-only. Configure any provider firewall to permit the same approved paths before acceptance.
4. Check the staging deployment receipt and browser run. Review Actions results and logs for the full Rails application, deployment preflight and MSP fixtures. Hosted endpoint, billing and media fixtures record simulated evidence. Run deployed TURN and scanner probes on disposable hosts using the Batch D staging instructions. Use expiring ICE credentials and report sanitized outcomes.
5. Register consenting beta testers and assign scenarios. Give each tester their one-time code through an approved private channel. They redeem it on the control plane and open a short-lived synthetic account on the staging host. Use a disposable system for native Windows and macOS updates, recovery testing or remote access. Use synthetic data and sandbox integrations for commerce. Review submitted outcomes before recording them as verified and attach passing retests to any corresponding defects.
6. Review the readiness section for missing and failed evidence. Record promotion approval for the displayed revision only after all required checks pass. An authorized release workflow can check this approval immediately before promotion.

```sh
bin/rails runner script/lightek/release_assurance_promotion.rb -- ACTOR_ID CANDIDATE_ID SOURCE_SHA
```

The production workflow checks a combined MSP release before configuring SSH. Set the repository variable `LIGHTEK_RELEASE_PROMOTION_URL` to the isolated Gatekeeper control plane's HTTPS `/gatekeeper/release-promotion` endpoint, then set the workflow secret `LIGHTEK_RELEASE_PROMOTION_TOKEN` to the token in that control plane's dedicated Vault entry. Set its `LIGHTEK_RELEASE_PROMOTION_VAULT_SLUG` to that entry. The Vault entry grants only `ReleaseAssurance::ProductionPromotion` and purpose `production_promotion_verification`. Configure the token with at least 32 bytes of entropy.

Set the repository variable `LIGHTEK_RELEASE_ASSURANCE_CANDIDATE_ID` to the approved control-plane record before pushing the first combined MSP release to `main`. The manual workflow also accepts this ID as `release_candidate_id`. Gatekeeper checks the current `main` commit, confirms its Git tree exactly matches the tested candidate, and verifies approval against current evidence. Preserve the candidate tree when integrating it, including its candidate-only CI triggers. If current `main` adds other source changes, assemble and verify a fresh candidate before promotion. A workflow failure at this gate occurs before any SSH or production host changes.

## Expiration and rollback

Expiry or operator retirement revokes the beta portal immediately and queues the existing Gatekeeper server deletion workflow. A sweep removes the staging A record only when it matches the destroyed node. Failed or uncertain allocations must be reconciled against the existing Gatekeeper request before cleanup. Keep the candidate ref and acceptance records for audit and retesting.

Use **Staging rollback** to prepare a fresh disposable instance at an earlier approved revision. Approve its fresh Gatekeeper request, verify the restored revision, then retire the failed instance. Keep release records and evidence in the control plane. Staging rollback uses fresh synthetic data and never restores a production database.
