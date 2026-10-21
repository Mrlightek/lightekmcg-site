# Nevaeh Capability Web Console — Phase 7A.8E

The authenticated employee console exposes the existing YAML capability registry, trusted service catalog and read-only reconciliation service. It is a projection of the same contracts exposed in `bin/nevaeh`; it does not parse YAML differently or execute services.

## Routes

- `GET /employee/nevaeh/capabilities` — capability list (HTML/JSON)
- `GET /employee/nevaeh/capabilities/:key` — validated definition and reconciliation (HTML/JSON)
- `GET /employee/nevaeh/services` — trusted service inventory (JSON)

All actions use the employee authentication boundary plus `authorize! :read, Marlon::Ticket`. No routes permit configuration writes, code generation, execution, job dispatch, migrations or production promotion. Capability keys are validated by the shared registry; response content is escaped by Rails templates.

## Subsequent phases

Extend the shared services for approved draft editing and CLI/web parity, using CSRF protection, dedicated capability permissions, audit events and Gatekeeper for all executable operations. Do not infer runtime authorization from a `reviewed` file or YAML registration. Run a full authenticated HTTP security regression before any deployment.

## Phase 7A.8H — native HTML services presentation

`GET /employee/nevaeh/services` now renders a read-only HTML table inside the existing employee dashboard controller/layout. Request `GET /employee/nevaeh/services.json` for machine-readable services. Both paths require the same authentication and authorization. A catalog entry is informational only, not an executable grant. Do not add an `/employee/dashboard` alias; navigation must use the existing dashboard routes.
