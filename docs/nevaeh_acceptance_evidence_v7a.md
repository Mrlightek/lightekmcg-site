# Phase 7A.8Q — Acceptance Evidence Engine

Read-only audit of existing isolated reviewed-candidate bundles. CLI: `bin/nevaeh acceptance-evidence /tmp/nevaeh-reviewed-...`. Dashboard: `/employee/nevaeh/acceptance_evidence` (requires the existing admin permission and local/test access).

Checks generated service and Active Job against verification SHA-256 values, checks the original draft manifest against ticket traceability, and retains ticket acceptance criteria verbatim. All criteria remain `unverified` until a future trusted reviewer maps specific tests/evidence to a criterion. Passing candidate unit/job tests does **not** establish acceptance or approval.

Neither interface executes test code, modifies tickets, rewrites evidence, grants authorization, promotes code, dispatches jobs or allows production access. JSON report is derived on demand, not persisted as an approval. Reports are restricted to temporary reviewed-candidate bundles outside Rails.root. Missing, symlinked, oversized or inconsistent evidence is rejected or fails integrity.
