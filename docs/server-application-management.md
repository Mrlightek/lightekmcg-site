# Server and application management

Dashboard → Servers & applications → Create server & application opens the installer. Super admins can assign an application to a client account. Existing customer website quotas and the paid-order provisioning path continue to apply to their existing workflows.

- **New server:** choose a provider region and live-priced server size, then a saved application template. The initial allocator supports Linode with Ubuntu 24.04. It creates a durable provisioning request, allocates through Gatekeeper and installs the application in a background job.
- **Existing server:** choose its name in Destination to install a separate application without allocating compute. Existing servers can use any provider supported by Gatekeeper SSH transport.
- **Shared website:** Add website on a server uses an existing Rails installation, sharing its code and database. The plan's website allowance applies.
- **Register existing Rails installation:** records code that is already installed; it does not install code. A runtime means the installed Rails code, database and workers that serve one or more websites. The registration form uses explicit Gatekeeper routes to avoid a duplicated inferred route prefix.

## Application templates and images

Save a name and preview domain for each design. The standard Lightek Rails template reuses the established website installer. Docker templates accept a fully qualified registry image pinned with `@sha256:...`, an internal web port and optional Rails PostgreSQL/Redis services and Sidekiq worker. Each installation receives its own Compose project, loopback web port and persistent volumes. Docker hosts need Ubuntu package repositories and public DNS pointing to the server for certificate issuance. The installer uses Apache alongside existing native Rails applications; it refuses a domain already configured in Apache or Nginx.

Rails Docker images must include executable `bin/rails`; installation runs `bin/rails db:prepare` and precompiles assets when that task exists before starting `bin/rails server`. Non-Rails images retain their image's default command. Supply application-specific environment variables through a Vault secret containing an `environment` object, with consumer `Gatekeeper::Hosting::Launches` and purpose `application_install`. For private images, configure `LIGHTEK_FLEET_REGISTRY_SECRET_SLUG` using the existing fleet registry policy (`Gatekeeper::Fleet::Transport`, purpose `fleet_registry`).

Build Rails image packages this repository from a selected design branch or commit using the existing private-gem packager. It publishes a digest-pinned GHCR image and registers a template via an authenticated callback. It does not publish a customer fleet release or initiate customer updates. Build state and GitHub Actions progress are visible from the installer. A client design must live in the selected source branch; the preview domain identifies the design and does not copy a running site's content/database into an image.

Required build configuration:

- Application environment: `GITHUB_ACTIONS_TOKEN` with workflow-dispatch access to `Mrlightek/lightekmcg-site`.
- GitHub variable: `GATEKEEPER_APPLICATION_IMAGE_URL=https://CONTROL_HOST/gatekeeper/application-images`.
- GitHub secrets: existing `LIGHTEK_CI_APP_ID` / `LIGHTEK_CI_APP_PRIVATE_KEY` for private dependencies, plus `GATEKEEPER_FLEET_RELEASE_TOKEN` matching the control application. GHCR publication uses the workflow's `GITHUB_TOKEN`.

Run `bin/rails db:migrate` before serving the new Dashboard or starting updated workers. Ensure the default Active Job/Sidekiq queue is running. Existing native Rails apps stay on their native installer/update path; Docker is an additional per-application deployment choice.

## Recovery and mail

Application launches retain their template snapshot, domain and provisioning request. Retry installation reuses those records and the original server. An uncertain provider allocation retains the existing allocator's reconciliation guard. An installation is ready only after its installer passes acceptance; Docker installations additionally verify public HTTPS and the running image digest. Failed installations leave their server available for retry; deleting the server remains an explicit operation.

Server deletion waits for queued/running installations and marks their launch records deleted after provider deletion. Launch history and operation receipts remain available.

Both paid-order provisioning and Dashboard-created servers use the approved SMTP restriction request, filling in the server IP, application domain and registered hostname. It asks for outbound ports 25, 465 and 587 and commits to SPF, DKIM, DMARC, reverse DNS, rate limits and abuse protections. Submission is idempotent per provisioning request. Dashboard mail-ticket submission failures retry independently of a ready application. This support request does not itself configure mail authentication or remove provider restrictions.

## Verification

`ruby test/standalone/fleet_updates_test.rb` exercises actual models/services with an isolated SQLite database. `python3 -m unittest discover -s test/standalone -p 'fleet*_test.py'` covers managed scripts and packaging. Full Rails boot requires the private ecosystem gems. Actual provider allocation, Docker startup, public certificate issuance and image-build callbacks require the deployment's configured credentials and must be verified in develop before release.
