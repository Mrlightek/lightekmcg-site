# Build and extend capability APIs

Digital Factory turns explicit construction definitions and sample expectations into a versioned implemented service, worker, verifier and tests.

## Build your first construction

1. Open Digital Factory → Construction.
2. Create a named construction with an input schema and ordered transformation steps.
3. Add independent sample inputs and exact expected outputs.
4. Build; inspect its generated artifacts and verification.
5. Activate only a verified release.

```text
/build CONSTRUCTION_ID
/activate RELEASE_ID
```

The IDs are different records. Read the build receipt to obtain the release ID. Activation registers a real capability, which then appears in /capabilities and the live Guide reference.

## Run and schedule it

Use the factory UI to create a worker from the active construction, provide its typed inputs and run it. Delegate that worker with `/delegate sage /run WORKER_ID`. Execution uses the existing ticket, Gatekeeper and Dispatch boundaries.

## Extend application APIs

Ubuntu application adapters provide typed argv contracts for installed binaries. They are edited through application_adapters and validated before activation. They are not interchangeable with the factory's transformation DSL.

## Keep documentation attached

Publish a capability input_schema with the registration, a useful name/domain, examples in its tutorial, and verification/recovery details. The Guide generates a live reference entry for installed capabilities. Registrations without a schema remain visible as schema_needed and can create a documentation ticket. A catalog entry alone is not proof that every domain operation has a conversational adapter.

For the full construction DSL and examples, read the installed Nevaeh Digital Factory manual in Software Library.
