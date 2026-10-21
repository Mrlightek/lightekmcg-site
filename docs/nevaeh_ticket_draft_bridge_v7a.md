# Phase 7A.8M — Ticket-to-Capability Draft Bridge

`NevaehIntelligences::TicketCapabilityDraftBridgeV7a.preview(ticket:, capability_key:, root:)` connects an existing, persisted, GitHub-derived `Marlon::Ticket` (with a validated Work Order) to a manually selected, disabled YAML capability. The Phase 7A.4 development plan is test-environment-only and remains the authority for ticket traceability.

`generate(ticket:, capability_key:, destination:, root:)` invokes the existing Phase 7A.8K isolated scaffold generator and appends `ticket_traceability.json` and `TICKET_README.md`. It does not infer missing service implementations, satisfy acceptance criteria, make Gatekeeper authorization decisions, promote source, execute jobs, or deploy.

The interface is an internal Ruby service in this phase. CLI/web ticket selection will be added after the test-only Work Order persistence and authorization semantics are examined. No user-supplied issue prose is treated as executable code or instructions.
