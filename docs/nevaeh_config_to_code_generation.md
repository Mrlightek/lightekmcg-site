# Nevaeh configuration-to-code generation (Phase 7A.8K)

## Scope

Read a validated, disabled YAML capability using `YamlCapabilityRegistryV7a`, consult the trusted service catalog, and generate Rails-style Active Job **draft** classes, companion test placeholders, documentation, and a checksum manifest in a new isolated directory. The output is **not a functioning feature**; job implementations deliberately raise `NotImplementedError`.

## Interface

`NevaehIntelligences::CapabilityCodeGeneratorV7a.plan(root:, key:)` returns a JSON-compatible reconciliation-oriented proposal.

`NevaehIntelligences::CapabilityCodeGeneratorV7a.generate(root:, key:, destination:)` creates an isolated directory not inside the repository and returns the manifest. The destination must not already exist. No application files, Git indices, jobs, or databases are changed by the generator.

## Next contract

Require a reviewed service mapping, Gatekeeper authorization, real service code, tests, CLI/web commands, and verification evidence before treating a generated draft as operational. Generated code must not be promoted directly to production.
