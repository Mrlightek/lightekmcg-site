# Phase 7A.8O: reviewed metadata normalization implementation template

This is a deliberately narrow first functional implementation template, not AI-generated feature code. It consumes an existing **validated persisted ticket** and explicitly selected disabled YAML capability through `TicketCapabilityDraftBridgeV7a.preview`. Exactly one job using the service identifier `nevaeh.metadata.normalize` with no dependencies is permitted.

`NevaehIntelligences::ReviewedImplementationTemplateV7a.preview(ticket:, key:, root:)` validates. `generate(ticket:, key:, destination:, root:)` uses the existing ticket bridge to create the inert draft and immutable ticket evidence. It then adds `reviewed_candidate/` with a deterministic working metadata normalizer, Active Job wrapper, service unit tests, README and checksum/verification record. The original draft manifest and ticket traceability remain unchanged.

Verification runs **only the reviewed static service unit tests** in a Ruby subprocess with `--disable-gems`. The Active Job integration and acceptance criteria remain **unverified**. Generated artifacts are never promoted, dispatched, authorized, or installed into the Rails app.

No CLI or web action is added in this phase. A later phase may expose this service after authenticated and gated integration tests.
