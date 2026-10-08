# Lightek Studio Blueprint System

## Product law

**What should Marlon have to do to create something?**

Minimize that work. Backend complexity belongs to Lightek.

A Studio blueprint describes creative intent once. The compiler normalizes
that intent into a canonical Studio contract. The generator materializes the
repetitive architecture around that contract.

## Flow

    Canonical Studio Blueprint
            |
            v
    Studio::Blueprint::Compiler
            |
            v
    Compiled contract
            |
            v
    Studio::Blueprint::Generator
            |
            +-- Worker
            +-- Nevaeh capability seed
            +-- Gatekeeper contract
            +-- PWA contract
            +-- Input JSON schema
            +-- Studio template
            +-- Worker contract test
            +-- Generated documentation
            +-- Compiled manifest
            |
            v
    Marlon::GeneratedArtifact provenance

## Canonical source

Blueprint source files live in:

    config/studio/blueprints/

The contract schema is:

    config/studio/schemas/blueprint.schema.json

## Generation

    bin/rails generate studio:blueprint character

By default this reads:

    config/studio/blueprints/character.json

An alternate source can be supplied:

    bin/rails generate studio:blueprint character \
      --source=config/studio/blueprints/character.json

Generated files are overwrite-protected. Explicit regeneration uses:

    bin/rails generate studio:blueprint character --force

## Safety boundary

Generated Nevaeh capabilities default to disabled unless the canonical
blueprint explicitly enables the runtime.

A generated worker delegates through `Studio::Blueprint::Runtime`.
Execution does not silently succeed when a backend handler is missing.
It raises `Studio::Blueprint::Runtime::ExecutionNotConfigured`.

That lets UI contracts, schemas, templates, and capabilities exist before a
dangerous or expensive production backend is activated.

## Provenance

Every generated artifact is registered through
`Marlon::Blueprint::FileWriter` and `Marlon::GeneratedArtifact`.

Provenance records include the Studio blueprint key, canonical source path,
source SHA-256, compiler version, generator class, generated path, and content
checksum.

Generated files should not become a second source of truth. Change the
canonical blueprint and regenerate.

## Nevaeh, Gatekeeper, and Blender

The blueprint describes intent and capabilities. Nevaeh resolves that intent.
Gatekeeper remains the authorization boundary. The generated worker remains a
thin execution adapter. The configured Studio execution handler owns actual
production behavior. Blender remains the authoritative high-fidelity runtime
whenever the blueprint uses the Blender provider.
