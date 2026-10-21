# Nevaeh Generator CLI + Web (Phase 7A.8L)

- `bin/nevaeh draft KEY` prints a read-only proposal from the shared generator.
- `bin/nevaeh draft KEY --write --destination /absolute/new/directory` creates inert draft artifacts in a new directory outside the repository. It never promotes code or dispatches jobs.
- `GET /employee/nevaeh/generator` previews saved capabilities, `?key=...` displays the plan, and `.json` offers machine-readable data.
- `POST /employee/nevaeh/generator` uses the same generator service to create a draft in a new randomized system temporary directory. The POST requires admin authorization, normal Rails CSRF, and a local Rails environment.
- CLI and web generation are prohibited in production. Gatekeeper execution authorization remains separate. Generated Ruby raises `NotImplementedError`.
- Draft generation is not implementation verification. Never treat generated test placeholders as passing feature tests.
