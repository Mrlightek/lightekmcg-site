# Nevaeh capability reconciliation — Phase 7A.8C

**Principle:** Configuration declares desired capability state. Reconciliation reports how that state compares with trusted service registrations and implementation files. Neither configuration nor reconciliation grants execution permission.

## CLI

```bash
bin/nevaeh config reconcile studio.asset.ingest
bin/nevaeh --format json config reconcile studio.asset.ingest
```

The command is **read-only**. It reports each job's `id`, logical `service`, `depends_on`, `state`, and `action`. `unmapped` means no reviewed mapping exists; it must **not** be confused with a missing service. `missing` means a trusted mapping names a file not found in the repository. `present` means the mapped file exists, not that it is implemented, tested, safe, or executable.

The Ruby service accepts a reviewed `service_paths:` mapping of logical IDs to repository-relative Ruby service files. **No mapping is auto-inferred from untrusted YAML.** The initial CLI intentionally supplies no mappings: it reports `unmapped` until a trusted service registry is implemented. Neither this command nor the reconciler loads Rails, invokes Ruby constants, executes generated code, dispatches jobs, modifies files, queries GitHub or touches production.

## Next implementation

Implement an approved, versioned service registration catalogue, inspect mapped services without invoking them, produce isolated Rails generator plans for missing services, and verify CLI/API/KB documentation, tests and Gatekeeper authorization before any execution is enabled.
