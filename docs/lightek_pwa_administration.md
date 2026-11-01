# PWA administration

Open **Dashboard → Workspaces → PWA Administration** (`/dashboard/pwa`). The host dashboard has a custom sidebar; its PWA link is rendered directly for platform super admins, authorized site administrators and remote installation owners. FeatureRegistry registration alone does not populate this sidebar. There are also entry points from Settings, Website Settings, the Business Command Center, application installations, and the PWA's service links for authorized administrators.

Select the website/application before editing. Configuration belongs to that site, not to the global PWA template records. A client's edits cannot rename or disable another client's application. Existing shared-site and native application provisioning initializes a named PWA configuration for each new website; existing websites receive their own defaults automatically and persist configuration on their first save.

## Controls

- **Overview:** actual site counts, seven-day posting activity and a saved-brand preview.
- **Settings:** app/home-screen names, description, logo/install icon, colors, support address, welcome text, start page, published/maintenance state, page availability, headings, supported section labels/order/visibility, and featured content record selection. Featured content still observes each viewer's audience and membership permissions.
- **Navigation:** enabled links, labels, order, primary/tools/footer placement, and custom internal or HTTPS links. Known surfaces remain subject to feature and entitlement checks. The site-specific install manifest is served at `/api/lightek/pwa/manifest`.
- **Content:** searchable, paginated post editing, moderation, visibility, audience and attachment review/removal and explicit post/reply deletion. Hiding a post also blocks its public permalink, attachments and replies through the shared access policy.
- **Communities:** settings, private/public and women/men audiences, active/suspended state, enabled community sections, add/remove members, member/admin roles and administrator-only community deletion. Owners are protected from accidental demotion. Creation uses the existing PWA publishing interface for that hostname.
- **People:** members, application roles, invitations to existing accounts, and application-specific suspensions. These do not change someone's global account role or private gender preference. Existing agency managers/designers/marketers inherit application admin/editor/moderator access; an application suspension overrides delegated PWA access. Owners and platform super admins retain authority.
- **Studio:** searchable projects, asset/error review and retry, guarded deletion of unused assets, artifact review, publication status/cancellation and operation cancellation. Site owners and editors can manage their site's Studio projects/assets, while platform super admins retain all-project authority. Running Blender/FFmpeg operations poll their cancellation state and terminate the process group; a cancelled operation is not silently revived by the preview worker. Cancellation does not issue an automatic payment refund. A late payment callback preserves cancellation and marks the operation for billing review rather than restarting it.
- **Live:** stop an active broadcast and hide its playback. Draft sessions cancel immediately; running capture sessions observe the stop at the next server heartbeat. The stop also applies to a platform super admin's active stream.
- **Conversations:** close/reopen site-bound community/watch-party discussions for new messages. Existing history remains readable to authorized participants. Personal direct-message bodies are not exposed.
- **Audit:** actor, action, record and changed field names for PWA administration changes. Raw post bodies, private gender settings and secrets are not copied into audit details.
- **Integrations:** entry points into the existing website, commerce, mail, live, billing, installation and network workspaces. Their existing permissions/paid entitlements remain in force.

For native installations on other servers, the dashboard lists authorized installation domains and opens that installation's own PWA administration. Settings/content are stored in the installation's database; this does not pretend that editing a central database updates an independent remote database. Use the installation's owner account. Fleet deployment/update remains Gatekeeper's existing workflow.

## Access and runtime

Platform super admins retain access across all sites and are not blocked by application maintenance/suspensions. Tenant owners can administer their own PWA even when their global account role is `client`. Editors can configure appearance/navigation and Studio/content; moderators can moderate content, communities, live and discussions; member-access changes require an application admin. All record lookups derive their site from the authorized dashboard selection. Personal profile identity remains shared-account data rather than tenant-editable account data.

Maintenance, member suspensions and disabled features are enforced by PWA APIs/capability dispatch and relevant workers, not only by navigation. Legacy post/community routes and completed receipts observe the application access state. Super-admin moderation visibility remains intact. The frontend applies host branding, install metadata, navigation, headings and supported layout controls, and blocks disabled routes. Reload the PWA or use its Refresh action to fetch saved configuration. The service worker never caches private API/manifest responses.

## Deployment and verification

Apply `20261031213017_add_lightek_pwa_administration.rb` and restart Rails, Sidekiq and the standalone Action Cable process. No storefront reseed is required. The migration version is checked against every host migration to avoid the timestamp collisions repaired in PR #166.

```sh
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/pwa_administration_checks.rb
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/media_checks.rb
python3 test/operations/migration_versions_test.py
```

The standalone Rails harness runs actual models, policies, migrations, controllers and ERB with only private host authentication/layout boundaries substituted. It can capture actual dashboard markup for Playwright with `PWA_ADMIN_CAPTURE_DIR=/tmp/lightek-pwa-dashboard`. Browser checks cover the actual rendered forms, mobile layout, branding changes and disabled/maintenance client behavior. Media checks execute actual FFmpeg/Blender and process cancellation. CI includes both isolated tests and a native-host PostgreSQL/Redis job using the existing private-dependency credentials.

The native-host integration tests in `test/integration/pwa_administration_test.rb` verify client-owner and super-admin access through the real dashboard/session stack. The full private dashboard gem, production layouts/feature-plan resolution and deployed cross-installation navigation still require native-host acceptance; isolated tests are not a production deployment claim.

## Website domain binding

Customer provisioning stores the requested public DNS hostname and initializes that site's PWA. IP literals and local/internal hostnames are rejected by the installer, hosted-site bootstrap and production Site validation. Existing legacy rows can still be edited without forcing a hostname change; a new or changed production hostname must be valid.

The normal deployment and fleet update paths run `lightek:site_binding:verify` with the deployment's expected domain after migration. An HTTP `/up` response alone is insufficient: the domain must resolve to an actual website row, and that row must have its own PWA configuration. Missing bindings stop deployment acceptance with an explicit error, without guessing which site's content to move. This check does not update DNS or certificates.

For a legacy site such as the imported `192.168.64.2` record, a platform super admin can select it in PWA Administration and click **Use [current dashboard domain] for this website**. The target comes from the request serving the dashboard, not a submitted hostname. The action keeps the same site ID, pages, posts, communities and PWA settings, checks the expected previous hostname and unique domain, and writes an audit event. Ordinary tenant owners/editors cannot rebind a domain. Public-domain sites and provisioning-managed identities must use the existing Network & Domains workflow so infrastructure reservations do not drift.

No hardcoded Lightek production hostname is substituted into customer records. No data migration or reseed is needed for this change. Full authenticated production acceptance still requires deploying it and using the repair control on the affected installation.
