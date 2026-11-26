# Studio recipe bindings and storage

Studio stores built-in recipes in `config/studio/recipes`. Both v2 examples conform to
`config/studio/schemas/recipe.schema.json`. The Ruby validator also checks declaration order and validates values at execution time.

```json
{
  "inputs": {
    "layer_name": {"type": "string"}
  },
  "steps": [
    {
      "command": "layer.newSolid",
      "params": {"name": {"$input": "layer_name"}},
      "returns": {"animated_layer": ["layer"]}
    },
    {
      "command": "prop.addKey",
      "params": {"layer": {"$ref": "animated_layer"}, "path": "transform/position", "value": [48, 90], "time": 0, "timeBase": "comp"}
    }
  ]
}
```

- `returns` maps each handle to a path within the engine command's result. Paths use string keys and zero-based array indices. An empty path captures the whole non-null result.
- `$ref` resolves only to a prior step's named result. Unknown and forward references and duplicate declarations fail before launching the engine. A missing or null result fails before the next step and leaves the requested output unpublished.
- `$input` resolves a declared input from the caller's `inputs:` hash or its explicit default. Missing required inputs and invalid values fail before launch. The two built-ins supply fixture defaults. A tenant-authored recipe can omit the default and require a runtime value.
- The existing `$param` default and override contract remains available. `Recipe#commands` expands parameters and inputs. Result handles are resolved by `run!` against the replies of a single live engine process.

## What changes at execution

The CLI's batch arguments are prepared before any result exists, so bound recipes require a persistent process. PhotoCraft uses `photocraft-cli serve --no-gpu` over JSON lines. EffectCraft uses `effectcraft-cli mcp` over stdio. Both give the same recipe executor a command result in time to prepare the next step. Commands retain their own parameter names and semantics.

PhotoCraft's session clears the polygon selection when creating its layer mask. The new recipe omits the redundant deselect command. The engine adapter accepts the exact no-selection response as a no-op for recipes that still include that command. The recipe captures the group ID from `layer.new.group` and selects that group, then captures the pixel layer ID and uses it for the mask, transform and opacity. Its `mask_path` input is a polygon of points in document coordinates. EffectCraft creates a solid using a caller-supplied display name, then passes the returned layer ID into both keyframe commands. Both result files retain editable engine state.

## Session deadlines and command discovery

A step may set `"timeout": 10` for a ten-second timeout. The default is 30 seconds per step and the default ceiling is 90 seconds per recipe. `run!(total_timeout: ...)` can set the ceiling. Startup, execution, saving and shutdown share that ceiling. Each operation uses the smaller of its own timeout and the remaining budget.

Execution failures raise `Studio::RecipeSession::StepError` with a zero-based `step_index`, the `command`, the `engine`, the `reason` (`:timeout`, `:died`, or `:protocol_error`), and the final 1,000 characters of stderr. Lifecycle and command discovery errors have a nil index. Recipe definition and binding validation continue to raise `ArgumentError`.

Both adapters expose `available_commands`, returning a registry keyed by command ID with an engine-provided `params` signature. EffectCraft also supplies the command's JSON Schema. Execution, command discovery, document opening and saving all use the selected engine's own protocol.

The health check observes whether the subprocess has exited. A running process may be wedged, may have closed its command channel, or may exit just after the check. Closed channels are handled on I/O and an unresponsive command fails at its deadline. The health check sends no protocol ping.

## Tenant recipe catalog

`Studio::RecipeRecord` stores site ownership, name, a positive integer version, the JSONB body, an optional source tutorial reference, and a publication flag that defaults to false. The foreign key follows Studio's existing `DymondSite::Site` boundary. A database unique index enforces one record per site, name and version. The record validates the recipe body and requires its name and version to match the row.

`Studio::RecipeCatalog.for_site(site)` returns all built-ins and the latest published version of each name for that site. Built-in and tenant entries have separate menu keys, so a tenant can use the same display name without replacing a built-in. The caller supplies an already authorized site.

## Verification

The headless checks compare PhotoCraft 0.23.1's PNG to an independently entered CLI sequence and compare the preserved layers, mask and source pixels. They also render a second caller-supplied polygon and verify the result changes. The EffectCraft 0.25.1 checks use an independently entered CLI sequence to compare keyframe data and CPU PNGs at 0, 1 and 2 seconds.

```sh
PHOTOCRAFT_CLI=/absolute/path/to/photocraft-cli \
EFFECTCRAFT_CLI=/absolute/path/to/effectcraft-cli \
ruby test/standalone/studio_recipe_checks.rb

PHOTOCRAFT_CLI=/absolute/path/to/photocraft-cli \
EFFECTCRAFT_CLI=/absolute/path/to/effectcraft-cli \
ruby test/standalone/studio_recipe_session_checks.rb

STUDIO_RECIPE_TEST_DATABASE_URL=postgresql:///studio_recipe_test \
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/studio_recipe_storage_checks.rb
```
