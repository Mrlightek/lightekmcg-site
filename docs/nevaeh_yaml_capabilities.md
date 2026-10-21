# Nevaeh YAML Capability Registry — Phase 7A.8B

**Architecture:** Nevaeh is a configuration-driven, self-documenting capability operating system built on Ruby on Rails. Capability YAML represents **desired state**, not authority to execute. Its jobs reference services by declarative identifiers; Ruby and Rails supply implementations. Gatekeeper is the independent authorization boundary; DymondDispatch is the orchestrator.

## CLI commands

```bash
bin/nevaeh help
bin/nevaeh --format json config list
bin/nevaeh config create studio.asset.ingest
bin/nevaeh config create studio.asset.ingest --write
bin/nevaeh config show studio.asset.ingest
bin/nevaeh config validate studio.asset.ingest
bin/nevaeh config job-add studio.asset.ingest validate studio.asset.validate --write
bin/nevaeh config job-add studio.asset.ingest process studio.asset.process --after validate --write
```

`create` and `job-add` are **preview-only** without `--write`. Writes create/update YAML only under `config/nevaeh/capabilities` and only on a local repo (the CLI rejects `RAILS_ENV=production` and `RACK_ENV=production`). No Rails boot or execution occurs. A draft is always disabled and requires Gatekeeper. Registration does not imply that a service exists or is safe to call.

## Schema and future work

Version 1 requires `schema_version`, `capability.key`, `version`, `enabled: false`, `authorization.gatekeeper_required: true`, `authorization.production_execution: false`, `jobs`, `cli`, and `documentation`. Each job has a unique `id`, logical `service` identifier, and an ordered list of earlier-step `depends_on` identifiers. This constrained ordering prevents cycles in the initial schema. No YAML is evaluated as Ruby and no arbitrary service class is resolved.

**Not implemented in this phase:** approved runtime service allowlist, Gatekeeper execution authorization, retries/timeouts, compensation, evidence receipts, ticket escalation, full autonomous reconciliation, live KB updates, or production deployment. Those belong in later schema versions with tests and documentation. No capability may become operational based on YAML alone.

## Definition of done

Every future capability must have CLI discoverability, help, JSON output where applicable, authorization enforcement, negative and positive tests, and documentation explaining what it does and how it works. Successful operational verification must precede a claim that a capability is runnable.

## Read-only reconciliation (7A.8C)

Run `bin/nevaeh config reconcile KEY` or `bin/nevaeh --format json config reconcile KEY`. The initial CLI reports unmapped service identifiers until a separately reviewed registration catalogue is available. It cannot execute, generate or deploy capabilities. See [Reconciliation](nevaeh_capability_reconciliation.md).
