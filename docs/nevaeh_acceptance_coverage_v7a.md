# Phase 7A.8R — Acceptance criteria coverage mapping

Read-only, opt-in local/test report: `bin/nevaeh coverage-report /tmp/nevaeh-reviewed-...`, or `/employee/nevaeh/coverage` in DymondDash. Requires the same local access and admin privileges as Acceptance Evidence.

Optionally place `coverage_mapping.json` in the isolated reviewed bundle root:

```json
{"schema_version":1,"mappings":[{"criterion_index":1,"evidence_type":"service_unit_tests"},{"criterion_index":2,"evidence_type":"job_integration_tests"}]}
```

Only these two evidence identifiers are recognized. Criterion indexes are 1-based in the existing ticket traceability order. A link is a *proposal*, never an independent assertion of requirement satisfaction. A passing test with a mapping is reported `mapped_pending_independent_review`. Missing mappings show `unmapped`; missing/tampered artifacts show `integrity_failure` or `evidence_unverified`. Mapping documents are untrusted, validated on read, and never used to execute Ruby. No ticket mutation, code promotion, approval, or Gatekeeper action occurs. CLI and web share the same service; JSON is available via `.json`.
