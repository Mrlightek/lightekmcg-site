# Studio operation catalog

`Studio::OperationCatalog.for_site(site, engine_adapters:)` returns thick authored operations and thin commands for that site. The caller passes an already authorized `DymondSite::Site`. The default adapter configuration uses `STUDIO_PHOTOCRAFT_CLI` and `STUDIO_EFFECTCRAFT_CLI`. An injected adapter implements `runnable?`, `available_commands` (a map keyed by command ID), and `executable` for thick execution.

Each entry provides its ID, display name, surface, source, schemas and CLI availability. Use the `:thick` entries for the default authored menu. The thin entries provide `hidden` for internal commands in the expanded command list.

## Thin operations

Thin entries use IDs such as `photocraft:select.lasso` or `effectcraft:prop.addKey`. The process-local read-through cache refreshes successful registries after 60 seconds and retries failed discovery after 5 seconds. When a CLI goes offline, the last-known signatures remain visible as unavailable. On a cold outage the catalog can show unavailable commands referenced by authored operations. Other commands need a successful discovery to populate the cache.

Authored overrides live in `config/studio/command_schemas/photocraft.yml` and
`effectcraft.yml`. Keys are full thin-operation IDs. For example:

```yaml
photocraft:select.lasso:
  typed_params:
    points: {type: polygon, unit: px}
  requires: [active_selection]
```

`typed_params` accepts number, string, boolean, color, enum, point and polygon controls.
Number and point specs can declare min and max. Enum specs use `values`. Defaults are checked against the type and bounds at load.
`params_signature` still gives the engine text. The effective `params_schema` uses JSON Schema, with `studio_type` for color, enum, point and polygon, and keeps the engine's untouched properties and top-level constraints. `typed` is true if at least one property has typed metadata or the engine declares an empty parameter object. A partly typed entry may still contain opaque properties. Missing types are logged as a summary and the commands remain in the catalog. Registry membership is verified against live discovery or the last successful inventory. Without either, a cold offline engine defers that particular check until discovery succeeds.

`applicable?(context)` checks the declared runtime flags for literal true. The supported flags are `open_document`, `active_selection`, `selected_layer`, `selection_or_mask`, `open_composition` and `timeline_playhead`. The caller computes each flag, including `selection_or_mask`. The vocabulary covers current context only. It cannot declare a dependency on a specific prior step, a particular mask or layer ID, or a state transition the recipe itself must produce.

PhotoCraft's prose leaves unannotated parameters untyped. EffectCraft exposes partial JSON Schema, including fields documented only in descriptions. For example, the value supplied to `prop.addKey` depends on the target property. The authored vocabulary covers simple shapes and constraints. It cannot describe polymorphic engine values, cross-field alternatives, or document-dependent option lists.

## Thick operations

A built-in YAML file contains the operation ID, display name, surface, description, a full recipe, and an `exposes` list. The two example recipes remain available as JSON. Catalog checks exercise both forms against the same engine outputs.

```yaml
exposes:
  - parameter: color
  - input: mask_path
```

An entry may also rename a public key with `as: Beard Width`, or fix the internal binding with `value: 0.45`. The same forms work for recipe inputs. A fixed binding is absent from the public schema, validated under the recipe's rules, and applied instead of the default. The original recipe binding can appear once, and public names must be unique. A required input without a default must be exposed or fixed. An entry maps a single public value to a single recipe binding. It cannot compute values, fan one value out to several internal controls, or change which controls appear at runtime.

Tenant operations are versioned, site-scoped JSONB records. The newest published version for an ID and surface is eligible for the menu. A tenant entry takes precedence over a built-in of the same surface with a matching ID or matching display name. Both remain accessible through `Studio::OperationCatalog.find(site, id, origin: :builtin)` or `origin: :tenant`. Use `surface:` to disambiguate an ID used on several surfaces.

## Verification

```sh
export PHOTOCRAFT_CLI=/absolute/path/to/photocraft-cli
export EFFECTCRAFT_CLI=/absolute/path/to/effectcraft-cli
export STUDIO_RECIPE_TEST_DATABASE_URL=postgresql:///studio_recipe_test
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/studio_operation_catalog_checks.rb
ruby test/standalone/studio_recipe_session_checks.rb
ruby test/standalone/studio_recipe_checks.rb
```
