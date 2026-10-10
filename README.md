<!-- LIGHTEK README V2 -->
# Lightek Media & Communications Group

**Lightek is a database-centered operating ecosystem for media, software, infrastructure, business operations, and the production of new capabilities.** This repository is the Rails host for its shared services and client-facing experiences.

> **Nevaeh's intelligence is the database knowing what capability to dispatch for the intent Lightek receives.**

The canonical database represents live operational state. Nevaeh resolves intent and available intelligence; Gatekeeper authorizes the requested operation; DymondDispatch executes work; results, tickets, artifacts, and tests provide evidence for subsequent decisions.

```text
Human / system / client intent
          |
          v
Nevaeh -> intelligence records + capability registry + Knowledge Base
          |
          v
Gatekeeper authorization
          |
          v
DymondDispatch -> registered Rails worker / production runtime
          |
          v
Database state + artifacts + receipts + tests + tickets
          |
          +-------> Nevaeh observes and improves subsequent execution
```

## Start here

| Area | Responsibility | Entry points |
| --- | --- | --- |
| Nevaeh | Interpret intent and select registered intelligence/capabilities | `app/models/nevaeh.rb`, `app/models/nevaeh_intelligence.rb`, `app/services/nevaeh_orchestration/`, `app/services/nevaeh_intelligences/` |
| Gatekeeper | Authorization and policy boundary | `app/services/gatekeeper/` |
| DymondDispatch | Work-item execution and lifecycle | `app/services/nevaeh_orchestration/dispatch_service.rb` and the DymondDispatch integration |
| Lightek CRUD | Capability lifecycle and execution evidence | `app/services/studio/factory/` |
| Lightek Studio | Intent-first creation of projects, productions, scenes, assets, and capabilities | `app/services/studio/`, `public/lightek/` |
| Tickets and knowledge | Escalation, unresolved work, procedures and validated resolutions | `app/models/marlon/ticket.rb`, KB integrations |
| Test history | Record, import and compare test evidence | `bin/nevaeh-test`, `app/models/nevaeh_test_run.rb`, `app/services/nevaeh_intelligences/test_history.rb` |

This table includes **local in-progress files** and may describe features not yet merged or deployed. Consult the status section before treating a feature as available in production.

## Architecture principles

1. **Database as operational truth.** The live state, relationships and registered capabilities are queryable; documentation is not a replacement for the database.
2. **Intelligence is dispatch.** `NevaehIntelligence` associates an intent and operating instructions with a registered `NevaehCapability`; the associated handler performs the work.
3. **Govern every effect.** Gatekeeper authorization precedes execution. Descriptive JSON or database access does not grant authority to execute arbitrary code or SQL.
4. **One factory, many products.** Studio is the creation surface for creative outputs and new technical capabilities; don't introduce a separate product for each creation type.
5. **Show the work.** Correlation IDs, work items, artifacts, test runs, and tickets make outcomes inspectable.
6. **Learning requires evidence.** Retain failures and compare subsequent runs; a recorded test is not, by itself, an autonomous self-repair system.

## Nevaeh: database-driven dispatch

```text
Intent
  -> published NevaehIntelligence
  -> enabled NevaehCapability + executable binding
  -> Nevaeh.handle(...)
  -> intent / knowledge / plan
  -> Gatekeeper authorization
  -> DymondDispatch work item
  -> worker / runtime output
  -> evidence, tickets, test history
```

Capability registration and intelligence synchronization are designed to share one transaction. Draft and archived intelligence should not be dispatchable. Handler readiness is required before a published capability is treated as executable. Test and ticket evidence should preserve *what ran*, *what happened*, and *what remains unresolved*.

### Lightek CRUD

Create, Read, Update, and Delete/Retire apply to more than database rows. For a capability, the complete lifecycle also includes generating an implementation, validating it, registering its execution contract, and demonstrating a working instance. Retire/Archive withdraws availability without destroying historical evidence.

### Lightek Studio

Studio is the intent-first creation interface and digital factory, not an isolated application. Its project-creation worker constructs a project, production and scene together; blueprint contracts describe generated capabilities and production plans. The browser provides an accessible control surface; Rails and registered production runtimes perform canonical operations. Some Studio panels remain visual/fixture-first pending further backend wiring.

## Current implementation status

*Snapshot: 2026-10-10. Source: local development test output and the earlier deployed UI milestone. **Local validation is not production deployment.***

| Capability | Status | Evidence / limitation |
| --- | --- | --- |
| Studio UI waves 1–5 | **Deployed UI milestone** | Release `4744044` / Deploy Production #62 previously verified; many panels are not fully wired |
| Blueprint compile, generate, registrar | **Validated locally** | Registrar and compiler tests passed; generated runtime still needs a real registered handler |
| Capability CRUD | **Validated locally** | 3 tests / 13 assertions; does not establish autonomous construction |
| Nevaeh Intelligence dispatch | **Validated locally** | 5 tests / 14 assertions |
| Registrar → Intelligence synchronization | **Validated locally** | Combined 14 tests / 47 assertions |
| Project → production → scene execution proof | **Validated in test** | 1 test / 13 assertions; inline dispatch boundary, test records rolled back; not a live queued job |
| Test recorder | **Validated locally** | `bin/nevaeh-test` wrote a JSON report and log for a passing 5-test run |
| PostgreSQL test history importer | **Validated in test** | 4 tests / 8 assertions; migration applied to test database only, development ingestion not yet confirmed |
| Asynchronous task groups | **Contract tested** | Dependency/fan-out planning validated; durable grouped dispatch not established |
| Independent ticket implementation, repair, approval and deployment | **Not yet demonstrated** | Requires an actual queue-driven, authorized, observable end-to-end run |

**Release boundary:** the newer Nevaeh and Studio features listed above are present in the *local working tree* and should not be represented as committed or deployed merely because their tests pass. Production migrations and deploys require a deliberate release step.

## Developer setup

Use the versions and dependency sources pinned by the repository (`.ruby-version`, `Gemfile`, lockfile, environment configuration). The host application uses Rails 8, Ruby 3.3, PostgreSQL, Redis, Sidekiq, Docker Compose and ecosystem gems. Object storage and Studio runtimes depend on deployment-specific configuration.

```bash
bundle install
bin/rails db:prepare
bin/rails zeitwerk:check
```

For the configured container stack, inspect `docker-compose.yml` and the applicable environment files before starting services:

```bash
docker compose up --build
```

### Run tests with evidence

Prefer the local recorder when available:

```bash
bin/nevaeh-test test/services/nevaeh_intelligences/dispatch_test.rb
bin/nevaeh-test
```

Reports and full logs are retained under `tmp/nevaeh/test_runs/`. The runner records only invocations made through `bin/nevaeh-test`; direct `bin/rails test` invocations are not automatically captured. A separate importer (`NevaehIntelligences::TestHistory`) can ingest and verify saved reports into PostgreSQL **after the target database has been migrated explicitly**. Avoid importing test artifacts into production by accident.

Alternatively, standard Rails tests remain available:

```bash
bin/rails test
```

### Schema and deployments

Use Rails migrations for schema changes; never edit `db/schema.rb` as the sole migration mechanism. Run migrations in the intended environment and validate test results before promotion. This README does not assume any CI failure or deployment check is automatically blocking.

## Project tracking and evidence

`config/project_tracking/lightek_studio.json` is the Studio roadmap source and projects to tracking integrations and `Marlon::Ticket` records. A ticket should distinguish the request, work-item execution, tests, artifacts, approval, and actual release state. A passing inline unit/integration test is not proof that Sidekiq processed a job in production.

## Documentation

- [Full prior architecture and vision](docs/architecture/legacy-readme.md) — preserved from the previous README without edits, including narrative-state, audience-intelligence, projection, product laws, technology and terminology.
- `docs/nevaeh/` — development lineage and Nevaeh-specific documentation (where present).
- `config/nevaeh/` — self-model and development history configuration (where present).
- `config/project_tracking/lightek_studio.json` — active Studio planning manifest.

When a new capability is built, update its executable contract and tests first, then keep the relevant Knowledge Base documentation in sync. Documentation should describe validated behavior, not confer it.

---

**Lightek is the ecosystem. Nevaeh is the intelligence. Gatekeeper is the boundary. DymondDispatch is the execution plane. Studio is the factory. The database records reality.**
