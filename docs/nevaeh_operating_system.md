# Nevaeh operating workspace

Nevaeh now has one authenticated conversational front door at `/dashboard/nevaeh`. The supplied identity-wheel design is integrated with the application rather than served as a standalone demo. Normal sign-in lands here; explicit return URLs still win. The dashboard Nevaeh section links to it.

## Connected behavior

- Spoken input, optional spoken replies, a live voice visualizer, thought cards, source references, action receipts, personas, memory controls, mobile sheets and reduced motion.
- Explicit commands and selected ordinary phrases compile into structured commands. Unrecognized prose retrieves documentation or uses an available active native neural checkpoint. Neural text is always a draft and is never parsed into executable code or tool calls.
- CRUD contracts cover workers, writing profiles, inference models, language models, constructions, training datasets, tickets and owned personas. Imported sources are read/delete contracts; they are created through the importer and reviewed explicitly. The manifest is `NevaehOs::Resources::ENTRIES`.
- `/execute INTENT {…}` reaches the existing native PWA capabilities (Studio, Blender workspace, community, messages, social and Susu) using the same action mapping as `/api/nevaeh/execute`. It also reaches published, enabled `NevaehIntelligence` entries for administrators. Registry availability is required; missing entries are not silently created. Native workers keep their site/ownership rules.
- `/run ID` uses the existing WorkflowRunner → structured ticket → Gatekeeper → Dispatch pipeline. Existing active workflow schedules remain the mechanism for autonomous work. This change does not add an unrestricted autonomous planning loop.
- Studio writing, native neural drafts, construction build/verification/activation and native dataset approval/training/checkpoint activation are commands in the same workspace.
- General chat is not saved as personal memory. Categories start disabled. Enabling a category and saving an individual memory are separate decisions. Disabling a category deletes its memories. Consented memories can provide native-model context. Action inputs/results are retained separately as audit records, including fields explicitly submitted to CRUD, writing or neural commands.

## Execution and authorization

`Conversation → saved immutable NevaehOsAction → Gatekeeper → DymondDispatch → NevaehOs::Worker → existing domain service`

The OS capability binds to a saved action owned by an authenticated account. Both dispatch and the worker check current authorization. Caller-supplied actor identifiers never determine authority. Native site and origin context comes from the request host, and user/actor/site fields override submitted payload values. Resource names and writable fields are explicit contracts; there is no arbitrary constantization, SQL, shell, controller invocation or evaluation of model text.

Resource writes and receipts commit in one transaction. Duplicate requests with the same key reuse the saved action; changed inputs under that key are rejected. Existing downstream services retain their own idempotency and verification behavior. Submission receipts do not claim downstream success: the receipt endpoint follows Dispatch, workflow ticket or training status. A missing downstream record is reported as missing evidence. Failed actions require a new explicit request; polling never retries work.

The capability is registered lazily at first dispatch so boot does not require migrated tables. An existing disabled entry stays disabled, and a mismatched worker binding is rejected.

Decide and Reflect modes return a proposal for mutating commands. Operate/Converse executes explicit recognized instructions under the caller's existing permissions. Personas change presentation and native draft context; they do not grant capabilities.

## Documentation learning

1. `/learn https://docs.blender.org/...` retrieves one public HTTPS HTML/text page into an owned draft source.
2. `/read sources ID` displays the extracted content, final URL and checksum for inspection.
3. `/review ID` records the reference in the existing KB and marks the source reviewed. If it has at least five explanatory sections, it also creates a draft prompt/response dataset using the existing corpus factory. Short references enter KB without invented training examples.
4. Inspect the dataset, then `/approve ID`. `/train MODEL_ID {"dataset_id": ID, "epochs": 10}` uses the existing training job and held-out acceptance process.
5. `/checkpoint ID` explicitly activates a passing checkpoint. For new executable behavior, CRUD a construction with sample tests, `/build ID`, inspect verification, and `/activate RELEASE_ID` through the existing Digital Factory.

Retrieval uses software manuals and the caller's reviewed source documents. External source text remains reference data: it does not alter resource contracts, activate code or authorize actions. The fetcher accepts public IPv4 HTTPS hosts, pins the resolved address while retaining TLS hostname verification, validates every redirect, strips active HTML, and limits response size and timing. It sends no user cookies or credentials. IPv6-only sites, logins, JavaScript-rendered documentation, bulk crawling and arbitrary website-to-API generation are not implemented.

## Commands

Use `/help` for the full live vocabulary. Examples:

```text
create a Studio project called Opening Night
open a ticket about missing live captions
list workers
pause worker 12
/read inference_models 3
/update workers 12 {"lock_version":0,"status":"paused"}
/execute studio.workspace.blender.authoring.edit {"scene_id":42,"operation":"..."}
/write caption {"topic":"Opening Night"}
/model 2 Help me plan this production
/remember Preferences: Keep replies concise
```

Native capability payloads retain their existing domain API contracts; the Blender operation above is illustrative and must match the existing authoring schema. `/capabilities` reports the installed executable vocabulary, and `/resources` reports writable fields. Creating a worker still requires the existing supported structured section schema. This release does not claim every application controller or database model has a conversational adapter, nor unrestricted natural-language understanding. Additional domains should expose reviewed capability contracts rather than bypassing their services with generic table writes.

## Verification and release

Run `ruby test/standalone/nevaeh_os_test.rb`. This uses real OS models, migrations, Rails controller processing/CSRF and Gatekeeper with SQLite. The harness supplies controlled host role-policy and Dispatch adapters. It runs on Rails 8; the test-only migration translation also permits the available Ruby 3.2/Rails 7.2 verification environment. Production retains Rails 8 and PostgreSQL JSONB.

Run `node test/standalone/nevaeh_os_browser.cjs` with Playwright installed. `CHROMIUM_PATH` optionally selects an installed Chromium. Screenshots go to `tmp`. These checks use explicit API fixtures to verify layouts, escaping, CSRF request headers, mobile sheets and reduced motion; they do not claim production domain execution or real microphone verification.

Deploy using the normal migration and worker-update pipeline. Keep Dispatch workers running. The full application/private-engine bundle, PostgreSQL runtime, real microphone permissions, paid actions, production deployment and every domain's end-to-end acceptance remain outside the controlled local checks. No external AI service or inference server was added. The natal/transit wheel remains explicitly illustrative; approximate positions do not affect authorization, action selection or evidence. The five principle labels are presentation labels, with no fabricated numerical ethics scores.

## Console, Ubuntu applications and agent workforce update

Capability names are now executable instructions: `susu.list`, `/susu.list`, `/execute susu.list` and `show my susus` all resolve to the same native capability. A capability-shaped request that is absent or disabled returns an explicit error instead of documentation search. The native Susu query includes groups the actor organizes or belongs to. Results render as cards, and the evidence panel has its own full-width text layout rather than the transit icon grid. The CSS/JS version changes force a fresh fetch after deployment.

### Rails console

`/models` discovers installed ActiveRecord models; `/schema User` describes their fields. `/rails` parses Ruby model expressions with Ripper into typed operations, without evaluating arbitrary Ruby:

```ruby
User.where(role: "client").order(id: :desc).limit(10)
Marlon::Ticket.find(42)
User.count
```

For models that do not require specialized domain services, `create!`, `find(...).update!` and `find(...).destroy!` run normal model validations and callbacks under the current CanCan permissions. Credential fields are unavailable for inputs and redacted from record outputs. Query inputs are literal field hashes; raw SQL, arbitrary constants/methods, blocks and interpolation are rejected. Returned collections are limited to 100 rows. Financial, infrastructure, Studio and orchestration state use their domain capability API for mutations rather than raw table writes. This is a Ruby-style application console, not an unrestricted Ruby interpreter or shell. Administrators can use the data console; host package/application controls require `super_admin`.

### Ubuntu application fabric

`/ubuntu setup ffmpeg` performs installation, documentation import, activation of the shipped typed recipe and a real application version check as one operation. It preserves an existing active adapter. Packages without a shipped recipe remain documented drafts; setup never guesses arbitrary executable arguments.

```text
/ubuntu setup ffmpeg
/ubuntu status
/ubuntu search video
/ubuntu refresh
/ubuntu show ffmpeg
/ubuntu plan ffmpeg
/ubuntu install ffmpeg
/ubuntu docs ffmpeg
/ubuntu integrate ffmpeg
/app describe ffmpeg
/app activate ffmpeg
/app run ffmpeg version
```

The `ubuntu.<operation>` capability form also works, for example `ubuntu.install {"package":"ffmpeg"}`. `/capabilities` includes these actions and active application operations with runnable command buttons. Application IDs are used in direct capability slugs (`app.12.probe`) to avoid ambiguity in package and operation names.

Package operations run through a root-owned helper installed for the native application user, not by granting Rails a root shell or arbitrary APT arguments. The helper uses configured APT indexes, package metadata and dependency resolution; it verifies trusted Ubuntu origins, rejects planned package removals and keeps ordinary APT archive authentication enabled. Installation pins the selected package version and verifies the resulting installed version. It does not add repositories or run generic OS upgrades/removals. The installer's bootstrap dependency is `python3-apt`. Main deployment, new native instance provisioning and native fleet updates all install the same helper automatically.

Installing a package does not automatically make every function callable. `integrate` reads its installed documentation and binary inventory, records the reference in KB, and creates a **draft** application adapter. FFmpeg, Blender and Pandoc have initial typed operation recipes. Other packages retain their docs and require authored operation contracts. Operators edit `application_adapters` through the existing CRUD interface; changes invalidate activation. Activation validates executable ownership and the typed contract; it does not silently run the operations. Runtime commands use argument arrays, a minimal environment and the unprivileged application user. Application execution is not a container/OS sandbox.

FFmpeg provides version, probe and transcode operations. Pandoc provides version and conversion. Blender's initial new package recipe reports its version; full Blender authoring continues through the existing Studio capability APIs. These are deliberately explicit adapters, not a claim that documentation has become arbitrary executable code or that a small native language model understands every Ubuntu application.

The Application Fabric panel uploads inputs into the operator's application workspace. File parameters stay inside that workspace, reject symlinks/traversal, and output names cannot overwrite existing files. Results include download links for created outputs. Example after uploading an input:

```text
/app run ffmpeg probe {"input":"UPLOAD_FILENAME.wav"}
/app run ffmpeg transcode {"input":"UPLOAD_FILENAME.wav","output":"converted.mp4"}
```

Package changes and application output files are host effects; a database rollback cannot undo them. Receipts record package verification and process exit status, and an unsuccessful application process is marked failed. No package was installed on a customer/production host during local verification.

### Real agents and workers

Nevaeh, Sage, Muse and Warden now resolve to persistent agent identities for each account. Custom personas use the same worker interface. Every executable conversation carries its agent identity into the saved action. Agents retain visual/voice identity, instructions for native model context, enabled state, autonomy mode and optional capability assignments. An empty assignment list inherits the owner's permitted actions; explicit names/prefixes restrict the agent. Agents never elevate the owner's permissions.

```text
/agents
/delegate sage susu.list
/agent schedule warden 60 susu.list
/agent run WORKER_ID
/agent pause WORKER_ID
```

Delegation creates a real worker, immutable run snapshot and saved OS action. A run can call an existing structured worker (`/delegate muse /run ID`) or another executable OS command. Schedules share the existing `NevaehIntelligences::WorkflowSweepJob` minute sweep; no new scheduler daemon is required. A scheduled request explicitly enables scheduled autonomy for its agent. Durable time-slot keys prevent duplicate scheduled runs; pausing a worker or agent and revoking owner permissions are checked again before execution. A failed/blocked prior run pauses future scheduled execution for attention. A queued run does not claim completion: the parent receipt follows the agent action, nested Dispatch result, structured ticket or training job.

The operating workspace shows agent workers, intervals, last execution status, and Run/Pause controls. The existing Control Center links to the workforce. This is explicit task delegation and scheduled execution using existing capabilities; it does not add an unrestricted autonomous LLM planning loop.

### Deployment and verification for this update

Apply migrations `20261109140000_create_nevaeh_application_adapters` and `20261109141000_connect_nevaeh_agent_workforce`, restart the worker process, and use the normal native deployment/update path to install the host helper. Docker-hosted Rails applications are not granted host package access by this implementation; they need a deliberate host transport rather than installing software into an ephemeral container. Manual deployments that bypass the normal installer can run the root installer with the actual app root and unprivileged app user:

```sh
sudo python3 lib/scripts/nevaeh/install_package_control.py --app-root /var/www/lightekmcg-site --app-user lightek
```

Run `ruby test/standalone/nevaeh_os_test.rb` with FFmpeg available, `python3 -m unittest test.operations.nevaeh_package_control_test`, and the Playwright check documented above. Package installation tests use controlled APT adapters and an isolated installer filesystem; they do not install real Ubuntu packages. Native domain/queue interfaces retain the controlled persistence harness boundary. A real FFmpeg version/probe/transcode test verifies the unprivileged application runner separately from those adapters.

Implementation references: [Ubuntu package management](https://ubuntu.com/server/docs/how-to/software/package-management/), [APT archive authentication](https://manpages.ubuntu.com/manpages/jammy/man8/apt-secure.8.html), [python-apt package interfaces](https://apt-team.pages.debian.net/python-apt/library/apt.package.html).

## Change-driven watchers and the in-app Guide

The follow-up adds `/dashboard/nevaeh/guide`, `/guide TOPIC`, and `/describe CAPABILITY`. Dashboard navigation and Mission Control link to it. Thirteen authored tutorials cover the operating workspace, command discovery, agents/schedules, memory/voice, Ubuntu applications, watchers, Rails data console, Studio, writing, documentation/training, capability construction, other platform modules, and recovery. Installed module manuals are linked from the same page.

The reference is generated from the installed capability registry, resource contracts, built-in commands and owned application adapters. Each entry includes availability, permission, invocation pattern, usage, verification and recovery. Declared schemas and construction/application contracts supply fields; native worker-source hints are explicitly marked as incomplete. Missing input schemas remain visible as `schema_needed` and can prefill a documentation ticket. Disabled registrations, missing operating adapters and ticket-workflow-only capabilities are distinguished from directly connected operations. The Guide does not claim all legacy registrations already have complete authored schemas. New registrations appear without editing a sidebar; publishing their input_schema improves the reference automatically.

Watcher administration is host-super-administrator-only and remains scoped to the owning account and agent. Watchers support:

- `ubuntu_package`: selected package candidate version changes, optionally refreshing APT indexes first.
- `ubuntu_catalog`: newly available or changed packages in a specific query; incomplete catalogs over 1000 matches fail rather than baseline partial data.
- `ubuntu_sources`: additions/changes to configured APT sources; this does not discover Internet repositories or enable unknown sources.
- `github_repository`: a selected branch's commit changes.
- `github_account`: newly observed repositories under a user/organization; snapshots use stable GitHub repository IDs and are capped at 1000 accessible repositories.

The first successful poll establishes a baseline without executing responses. Subsequent changes create durable deduplicated events. Rules choose `new`, `updated`, or `new_or_updated`; responses are:

- `prepare`: produce a package dependency/download/disk plan, or a repository onboarding packet. `/watch apply EVENT_ID` explicitly dispatches the prepared package setup or opens the onboarding ticket. Applying an event before preparation prepares it first and requires a subsequent apply; it does not skip the review state.
- `update`: automatically dispatch the selected Ubuntu package's setup flow. This option is restricted to selected-package watchers, not whole-system updates or arbitrary new repositories.
- `command`: substitute whole-value event data into an explicitly configured command template and run it through the existing agent/Gatekeeper/Dispatch pipeline.

Polling uses leases and configuration fingerprints. Queued duplicate jobs cannot consume an active lease; stale results after pause or rule edits are discarded. Changes to target/condition/response/template/agent establish a new baseline, and old events cannot inherit a new execution policy. Current account and agent permissions are checked again for observation, planning and execution. Three consecutive sensor failures pause the watcher; resume after fixing the recorded error. Events retain before/after observations, plans, blocked reasons and agent-run links. Deleted entities do not trigger installation events.

The existing minute WorkflowSweepJob enqueues due watcher polls and recovers undispatched detected events. Watcher responses use real agent workers and immutable run snapshots. No new scheduler daemon or public webhook is required. Public GitHub reads need no credential; private reads use a Vault checkout authorized for consumer `NevaehOs::WatchSensors` and purpose `nevaeh_repository_watch`. The watcher does not widen Vault policies. User-account private discovery requires the selected user's token; an existing platform GitHub App credential may be scoped only to the platform repository.

Apply migration `20261109160000_create_nevaeh_watchers_and_events`, update the package helper through the existing native deployment path, and restart workers. This follow-up includes the merged PR #205 foundation and has been reconciled with main at `2a0b985`, preserving the later provisioning, routing and schema updates. Polling, package changes and actual external installation/deployment were tested with controlled sensor/queue adapters locally, not against production accounts. Local tests verify the state transitions and permission boundaries; they do not claim live production watcher acceptance.

Commands and complete worked examples are in `docs/nevaeh/tutorials/watchers.md`. Run the existing OS Ruby suite, Python package tests, operating-workspace browser check and `test/standalone/nevaeh_guide_browser.cjs` after rendering its fixture via the Ruby suite.
