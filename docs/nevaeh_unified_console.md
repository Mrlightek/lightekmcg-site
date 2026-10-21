# Nevaeh Unified Dashboard — Phase 7A.8I

`GET /employee/nevaeh` is the read-only dashboard landing page. `GET /employee/nevaeh.json` returns the same underlying registry/service information for automation. Both require the normal employee authentication boundary and `authorize! :read, Marlon::Ticket`.

## Sources
- `NevaehIntelligences::CapabilityConsoleV7a.list` reads the YAML capability registry.
- `NevaehIntelligences::CapabilityConsoleV7a.services` reads the trusted service catalog.
- Links reuse existing Rails routes for capabilities, trusted services, and tickets.
- Jobs, documentation and configuration editing are not exposed as active routes until implemented and authorized.

## Security and operation

This is an inspection-only projection. Catalog entry `executable` is metadata, never a grant from Gatekeeper. No YAML edits, jobs, code generation, migration, Git operations or production dispatch occur in this phase. CLI commands continue to use the shared registry and service catalog. Verify sidebar visibility manually using an authenticated super-admin local session.
