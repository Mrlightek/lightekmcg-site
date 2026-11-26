# Studio Macro Maker API v1

All paths below use `/api/v1/studio/macro_maker`. The host's authorized request integration sets `request.env["lightek.studio.macro_maker"]` to `{site: site, user: user}`. The same trusted context may supply `engine_adapters:`; the controllers otherwise use the configured adapters. A request without the context receives a structured 403. Site and user IDs in the client request do not select an identity.

| Request | Success | Response |
| --- | --- | --- |
| `GET /catalog?surface=image` | 200 | Thick operations, supported surfaces and engine IDs. Each operation includes the union of its wrapped commands' context flags. |
| `POST /validate` | 200 | Pass `{definition: {...}}`. Returns `valid`, `compiled_recipe` and structured `warnings` without creating a record. |
| `POST /compositions` | 201 | Pass `{definition: {...}, published: true}`. Returns the saved record identity and version. Omitted `published` defaults to false. |
| `GET /compositions?surface=image` | 200 | Latest published version per operation ID and surface, plus the caller's own drafts. Each result includes the source definition. |
| `GET /compositions/:operation_id?surface=image` | 200 | Latest version visible to the caller, with source definition, compiled recipe, references and interfaces. |
| `GET /operations/:id?surface=image` | 200 | Published operation or built-in form definition and CLI availability. |

An existing built-in is shadowed in v1 by a published tenant operation with the same ID and surface. A request for a surface includes applicable `both` operations. Use the surface query for an ID present on more than one surface. A missing or invisible detail is a 404, including attempts to address another site's records. An invisible record does not affect a list. Existing ownerless drafts remain private until a record has an owner.

New saves allocate the next version for the site, operation ID and surface. The server sets this version in both the source definition and compiled recipe. Two equivalent saves create two versions. A site's version calculation and save run under a PostgreSQL row lock.

All error responses use `{valid: false, errors: [...]}`. Errors and warnings contain `step_index`, `step_operation_id`, `kind` and `detail`. Indexes are zero-based. Non-step errors use null location fields. A CLI outage can produce validation warnings while the chain remains valid. The catalog and run form serialize the Ruby `runnable?` predicate as `runnable`.

`params_schema` and `inputs_schema` are JSON Schema object definitions with `studio_type` annotations for specialized controls. `returns` and `accepts` are flat maps. Internal Ruby control maps continue to feed recipe validation. The versioned response schema lives at `config/studio/schemas/macro_maker_v1.schema.json`.

A client can reopen the source array of thick operations, their bindings, and captures. Expanded native commands are available in the validation and composition detail responses, but v1 does not specify how to associate each native command with a particular source step. A command-level visual editor would need stable step IDs, an expansion/source mapping, and per-step engine or validation state. Those fields could be supplied by a separate expansion view or a later API version.

## Verification

`test/standalone/studio_macro_maker_http_checks.rb` exercises the Rails routes with PostgreSQL, both CLI paths, and Python's `jsonschema` package for response validation. Set `PHOTOCRAFT_CLI`, `EFFECTCRAFT_CLI`, and `STUDIO_RECIPE_TEST_DATABASE_URL` before running it under `test/standalone/Gemfile`.
