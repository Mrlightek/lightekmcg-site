# Phase 7A.8J — Nevaeh browser configuration

The native DymondDash navigation adds **Configuration** at `GET /employee/nevaeh/config`.
Admin/super-admin authorization is mandatory for `GET /employee/nevaeh/config`, `POST /employee/nevaeh/config`, and `POST /employee/nevaeh/config/:key/jobs`.

The controller calls the same `NevaehIntelligences::YamlCapabilityRegistryV7a.create` and `.add_job` service methods used by `bin/nevaeh config create ... --write` and `config job-add ... --write`.
POST requests use ordinary Rails CSRF protections and signed session authentication. The existing registry validates identifiers, dependencies, and disabled status; it remains the authority for YAML validation.

The web interface refuses to operate in production. Drafts are always disabled and do not invoke workers, Gatekeeper, Ruby services, migrations, or Git operations. An admin saving a draft is not Gatekeeper authorizing its execution. No YAML editing beyond draft creation and adding jobs is supported.

Use `GET /employee/nevaeh/config.json` for read-only JSON inventory. Manual browser visual acceptance is still required. The controller does not attempt to make YAML writes atomic across multiple concurrently active processes; production authoring requires a future coordinated versioned configuration store.
