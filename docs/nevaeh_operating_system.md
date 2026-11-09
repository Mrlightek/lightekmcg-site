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
