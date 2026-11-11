# Commands, inputs and capability discovery

A capability is a named operation. A resource contract is an editable record interface. A worker is a saved procedure. A watcher detects changes and can trigger an agent worker.

## Run a capability

1. Enter `/capabilities` or search the live reference in Guide.
2. Open its reference. Check availability, permission, inputs and verification.
3. Copy the example into Nevaeh. Replace example IDs with records you can access.
4. Send it and inspect the receipt. Never infer success from a queued message.

```text
susu.list
susu.show {"group_id":123}
/execute susu.list
/describe susu.show
```

`group_id:123` is an example, not a real account record. Use an ID from your Susu list. Your identity is inserted by the server. When the host is not mapped and several applications are available, specify your authorized `site_id` in the inputs.

## Query and edit resources

```text
/resources
/read agents
/read workers
/read workers 12
/update workers 12 {"lock_version":0,"status":"paused"}
```

Read the current record before updating it. Use the returned `lock_version`; copying 0 after another edit will be rejected. `/delete RESOURCE ID` deletes the record subject to its model rules; it is not a pause command. Imported sources, agent workers and watchers have dedicated creation workflows.

## Know when a command is incomplete

Capability-shaped names do not fall back to unrelated documentation. An unavailable capability returns an explicit error. A missing input fails with its domain error. `/search Blender` explicitly searches documentation.

The live reference distinguishes declared input schemas, implementation-derived input hints, and schemas that still need publishing. Hints are not a complete or authoritative schema. Use the linked domain tutorial/manual and raise a documentation ticket from the reference if a schema is missing.

## Add new functionality

Activate a verified construction or application adapter. Its catalog entry is generated from the installed contract. The reference updates with the installed software; a new command does not need to be manually added to the Guide navigation.
