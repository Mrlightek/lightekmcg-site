# Marlon Meta-Framework

The meta-framework stores application architecture as data:

```text
ProjectType
  -> ProjectTypeCapabilityPack
    -> CapabilityPack
      -> CapabilityPackDependency
      -> CapabilityPackFeature
        -> Feature
          -> BlueprintConcern
```

## Install

```bash
bash install_marlon_meta_framework.sh
```

The script creates timestamped backups before replacing an existing file. Set
`FORCE=1` to overwrite without backups.

## Seed

```bash
bin/rails marlon:meta:seed
bin/rails marlon:meta:validate
```

## Inspect a compiled blueprint

```bash
PROJECT_TYPE=managed_it_services bin/rails marlon:meta:inspect
```

## Generate an application layer

```bash
bin/rails generate marlon:meta_framework managed_it_services Device
```

Generate only MDM and RMM, including their dependencies:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --packs mdm,rmm
```

Generate selected device functions:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --packs mdm \
  --features device_enrollment,policy_management,remote_lock,remote_wipe
```

Generate API controllers and policies:

```bash
bin/rails generate marlon:meta_framework managed_it_services Device \
  --api \
  --policies
```

## Builder integration

Your project builder should persist or pass:

```ruby
{
  project_type_key: "managed_it_services",
  capability_pack_keys: %w[mdm rmm ticketing],
  feature_keys: %w[device_enrollment remote_lock remote_wipe]
}
```

Compile that selection with:

```ruby
project_type = Marlon::ProjectType.find_by!(key: params[:project_type_key])
blueprint = Marlon::Blueprint::Compiler.new(
  project_type: project_type,
  selected_pack_keys: params[:capability_pack_keys],
  selected_feature_keys: params[:feature_keys]
).call
```

The compiler resolves dependencies in topological order and removes duplicate
packs and features. The generator records generated paths and SHA-256 checksums
in `marlon_generated_artifacts`.

## Extending the framework

Add new records rather than changing generator logic:

1. Create a `Marlon::CapabilityPack`.
2. Attach dependencies.
3. Create or reuse `Marlon::Feature` records.
4. Attach one or more `Marlon::BlueprintConcern` records to each feature.
5. Attach the pack to one or more project types.

A future renderer can inspect `BlueprintConcern#target_type` and
`#configuration` to generate serializers, GraphQL types, navigation, routes,
permissions, dashboards, or workflow definitions.
