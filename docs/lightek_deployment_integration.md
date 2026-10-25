# Lightek website deployment

The verified existing-Ubuntu deployer lives at `script/lightek/website_deploy.sh`.
`bin/lightek-deploy` loads configuration from the application's existing node or
provisioning-request metadata and owner User record. There is no new database
table. `script/lightek/library.json` documents the scripts-library entry point.

## Installation and current Octavia

Install locally with `APPLY=1 bash ~/Downloads/lightek_deployment_integration_install.sh`.
The installer installs source and runs the Rails autoload check and targeted
tests. Feature rows synchronize during application boot. It does not allocate
instances, read Vault payloads, or update Octavia.

To carry the boot-sync correction into Octavia, rerun the included deployer from
the Mac checkout after installation:

```bash
bash script/lightek/website_deploy.sh --owner-role super_admin
```

Use the existing hostname, SSH destination and owner email/password. The deployer
preserves existing site content and never resets an existing owner's password.
It adds missing sidebar section records from local configuration, preserving
existing labels. `--owner-role super_admin` explicitly requests internal ownership;
the default for customer installations is `admin`.

## Register an existing node

Use the Vault UI to store a secret with slug `octavia-website-deployment`.
Its payload contains `owner_password` (the deployed website owner's password)
and either `ssh_password` or `ssh_private_key` for the target server.
Alternatively the node may already have a usable `ssh_key_path`.
Never place these values in shell arguments or source code.

The secret policy must allow consumer `Gatekeeper::WebsiteDeployment` and purpose
`website_deploy`. Only that reference is persisted in deployment metadata.
The source application's existing `LIGHTEK_VAULT_MASTER_KEY` must be configured
for Vault checkout. Fresh target installations receive a separate randomly
generated Vault key; source keys are not copied. Existing target keys are preserved.

```bash
bin/lightek-deploy register --actor-id 1 --owner-id 1 --node-id 1 \
  --domain octavia.lightekmcg.com --name Octavia \
  --headline 'Media Server' --description 'OTT streaming service' \
  --certificate-email mrlightek@gmail.com \
  --credential-slug octavia-website-deployment --internal \
  --owner-email marlon@lightekmcg.com

bin/lightek-deploy preview --actor-id 1 --node-id 1 --domain octavia.lightekmcg.com
bin/lightek-deploy run --actor-id 1 --node-id 1 --domain octavia.lightekmcg.com
```

IDs are local application record IDs. Check that the actor and owner IDs identify
the intended operator and owner. `preview` reads configuration without checking
out secrets or allocating anything. `run` checks out credentials under Vault policy,
installs a temporary SSH public key using Net::SSH, reuses one OpenSSH master for
deployment, and removes the temporary authorization when the SSH session ends.
An interrupted process may require removing its temporary authorization manually.
Credentials are passed to the packager on stdin, not process arguments. The
configuration's owner email is resolved from the User record at execution time.
For an internal installation with an existing different sign-in email, the explicit
`--owner-email` alias is preserved in configuration. Customer deployments use their
owner's User record email.

## New customer instances

Create/configure the subscription-backed ProvisioningRequest through the existing
Dashboard workflow. Select its provider, region, plan, Ubuntu image, node label
and estimated cost. The same customer must own the request and the deployment.
Register website settings against that request using `--request-id` instead of
`--node-id`, the customer's `--owner-id`, and omit `--internal`.

```bash
bin/lightek-deploy preview --actor-id 1 --request-id REQUEST_ID --domain customer.example.com
bin/lightek-deploy provision --actor-id 1 --request-id REQUEST_ID --domain customer.example.com
```

`provision` is billable: it calls the existing ProvisioningExecutionService only
when the request is approved and ready. It requires the existing active, healthy
Linode provider and its Vault credential. It never grants approval or changes the
selected plan. It waits for the provider to report the node running, then deploys
to that node. The generated root credential remains governed by its existing Vault
policy, extended at creation to allow the website deployment consumer for
`node_bootstrap`. Existing secret policies are not silently changed.

If website deployment fails after allocation, the node remains attached to the
request. Retrying uses it instead of creating another instance. A failed allocation
with no saved node requires operator/provider reconciliation before changing its
request back to ready; never blindly repeat an ambiguous provider request.

The deployment machine needs Python 3, OpenSSH client/keygen, Net::SSH, Ruby/Bundler
and the full application checkout. This CLI initially runs from that checkout; it
is not yet wired to a Dashboard button or a background queue.

## DNS and resources

Existing matching public DNS is accepted. Otherwise the current Godaddy::DnsService
is used. The deployment Vault payload may include `dns_env` with its existing
`GODADDY_PAT` and `GODADDY_DOMAINS` values. These are supplied only to the local
deployment subprocess, not the remote website or image. Existing source-process
environment values still work. Unattended runs stop when DNS credentials/zone are
absent, allowing an operator to configure DNS and retry the same node. Conflicting
records are not overwritten.

Below 2 GiB RAM, the build uses currently available RAM plus free swap, reserving
256 MiB for the host. The builder is capped at 512 MiB RAM and 1536–2048 MiB combined
RAM+swap according to that available capacity, with half a CPU. Compilation is
serial. At least 900 MiB physical RAM and room for the minimum capped build are
required. New installations require 6 GiB free disk; updates to an existing managed
deployment require 3 GiB. Runtime uses one web process and one Sidekiq job at a time. Larger
servers use the standard build path, up to four compilation jobs according to RAM
and CPU count, three to eight web threads, and two to four Sidekiq jobs. Re-running
deployment after a resize recalculates these settings. No resizing is performed
and no swap file is created automatically. Select an appropriate plan or prepare
swap before deploying to a smaller new instance.

An operation succeeds only after the actual public HTTPS, CMS content and owner
login checks pass. Failures use the existing Gatekeeper KB lookup and support-ticket
services. This acceptance covers website delivery, not all application modules.

## Feature boot synchronization

The early boot hook defers FeatureRegistry database writes until after Rails has
set up its model autoloader. Definitions remain registered in memory during boot.
After initialization it synchronizes all registered definitions using the existing
FeatureRegistry method. With an absent feature table, synchronization is skipped;
it does not create replacement feature models or modify the gem installation.
