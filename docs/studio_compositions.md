# Studio compositions

`Studio::Composition.new(site:, definition:, catalog_options:)` creates a pre-save composition. `to_recipe` validates and compiles it. `save!(published: false)` creates a site-scoped `Studio::OperationRecord` using the existing publication and version rules. It saves the compiled recipe plus the source composition, public schemas and catalog references.

```yaml
id: studio.layer_example
name: Layer Example
version: 1
surface: image
description: Add a layer and set its opacity.
parameters:
  layerName: {type: string, default: Macro Layer}
steps:
  - operation: photocraft:layer.new.layer
    params:
      name: {$param: layerName}
    returns:
      working_layer: layer
  - operation: photocraft:layer.setProps
    params:
      layer: {$ref: working_layer}
      opacity: 0.5
```

Steps use `params` for parameters and `inputs` for a thick operation's inputs. The keys in a step's `returns` map are new composition handle names. The values are the operation's public output names. A handle may be used by any later step. A composition runs one engine session and supports image or motion authoring. Thick operations are expanded in place, including aliases, fixed values and defaults. Uncaptured internal handle names are renamed to avoid collisions. Captured handles also become public outputs when the composition is saved as a thick operation.

The catalog operation's `returns` map declares handle types. A thick operation can expose only handles that its wrapped recipe captures. Thin registries currently omit result schemas, so supported result names are verified against engine reply fields in the catalog's command result map. `accepts` is keyed by public parameter or input name. Each value names one handle type or a list of acceptable types. An undeclared binding falls back to its known native type. A command with an opaque parameter cannot take a handle there without an explicit declaration. `any` is valid only as an accepting type. Parameters and inputs still use the existing Recipe value types.

Validation aggregates problems as `Studio::Composition::Invalid#errors`. Each error includes the zero-based step index, operation ID, kind and detail. Errors about the composition itself use a nil step index. No record is written until both the chain and the resulting recipe validate.

Recipes returned by `Composition#to_recipe` and recipes opened through the persisted operation revalidate references before running. Catalog identity, contract metadata and the flattened recipe are checked against the saved compile result. Referenced tenant compositions are revalidated too. Raw recipe JSON is a portable engine program. To retain site-aware drift protection, run a composition through the composition or operation object that owns its metadata.

The handle model checks declared value categories. It cannot express a type that depends on another argument, a layer which must have a mask, or affiliations such as a layer belonging to a particular composition. Runtime engine state and operation preconditions remain distinct from handle compatibility.

## Verification

With the PhotoCraft and EffectCraft CLIs installed, run from the repository root.

```sh
export PHOTOCRAFT_CLI=/absolute/path/to/photocraft-cli
export EFFECTCRAFT_CLI=/absolute/path/to/effectcraft-cli
export STUDIO_RECIPE_TEST_DATABASE_URL=postgresql:///studio_recipe_test
BUNDLE_GEMFILE=test/standalone/Gemfile bundle exec ruby test/standalone/studio_composition_checks.rb
```
