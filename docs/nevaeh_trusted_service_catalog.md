# Nevaeh Trusted Service Catalog — Phase 7A.8D

`config/nevaeh/trusted_services.yml` is an independently reviewed list of logical service IDs and repository-relative service files. It is **not** a runtime execution allowlist and does **not** authorize a service to run. `review_required` and `reviewed` are review metadata only, not execution states.

## CLI

```bash
bin/nevaeh config services
bin/nevaeh --format json config services
bin/nevaeh config reconcile studio.asset.ingest
```

When a trusted catalog is present, reconciliation uses only its reviewed mapping. When absent (such as a temporary test workspace), reconciliation fails closed to `unmapped` for all services; the `config services` command still reports a missing catalog error. Capability YAML cannot supply implementation paths. All inspections are read-only, do not load service constants, and report presence/checksums only. A present file is **not** evidence of correct implementation or authorization. Catalog updates require normal source review. No execution, Gatekeeper grants, job dispatch, database changes or deployment occurs in this phase.

## Next

Add a separately authorized, explicit service activation policy (Gatekeeper), executor interfaces, failure handling, and web/API projection using these read-only registry services. For generated components, build isolated Rails generators with tests, docs and CLI contracts before considering a feature operational.
