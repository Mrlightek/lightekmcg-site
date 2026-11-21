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
Run capability susu.list
Run capability susu.show with {"group_id":123}
```

`group_id:123` is an example, not a real account record. Use an ID from your Susu list. Your identity is inserted by the server. When the host is not mapped and several applications are available, specify your authorized `site_id` in the inputs.

## Find a feature's implementation

Open **Dashboard → Software Library → Code map** or ask Nevaeh with `/code Studio CPU`, `/code payout accounts`, or `/code susu.list`. Both views require permission to manage Nevaeh workflows. The code map offers JSON export and lists source paths, workers, locked gem dependencies and verification references where available.

A mapped binding appears as enabled when its installed registry entry matches the worker, event, and Gatekeeper capability. For enabled entries, Nevaeh shows an example command. Replace placeholders such as `SCENE_ID` with IDs for records you can access. Submit the command through the normal conversation and follow the existing execution receipt. A render quote returns an operation and quote, and the render follows the existing Studio settlement workflow.

An architecture reference documents a workflow's source. Check Guide for execution routes outside the map. To extend the map, update `config/nevaeh/code_knowledge.json` with repository-relative references. Add a capability link after the shared native registry can resolve the action. For in-app operations, link to a named `NevaehOs::PlatformActions` entry. These commands use the saved-action worker, and authorization is checked at submission and execution. CI checks that source paths, gem references and both kinds of worker bindings resolve.

Examples of in-app operations include `/execute sales.lead.create`, `/execute reservations.availability.list`, and `/execute marketing.publication.schedule`. Use their code map examples for the exact inputs. A calendar receipt confirms a saved schedule. Provider delivery has its own status. A saved broadcast channel status reports configuration. Check the broadcast workspace for live stream health.

### Sales and publishing commands

| Task | Say or type |
| --- | --- |
| Check a lead and get its current version | `Show lead #12 on site #3` |
| Convert a qualified lead to a deal | `Convert lead #12 on site #3 at version 0 to a deal called "Spring launch" for 1500.00 USD closing 2027-03-31` |
| Check a quote and its order | `Show quote #42 on site #3` |
| Issue a draft quote | `Issue quote #42 on site #3 at version 0` |
| Record a customer's confirmed approval | `Record customer approval for quote #42 on site #3 from "Jane Doe" with reference "Approval email"` |
| Check payment, delivery, and installation status | `Check order #42 on site #3` |
| Finish fulfillment of a paid order | `Fulfill order #42 on site #3 with reference "Delivery receipt"` |
| Queue installation recovery for a paid order | `Retry installation for order #42 on site #3` |
| Check a calendar slot and get its current version | `Check publication slot #12 on site #3` |
| Cancel a pending local slot | `Cancel publication slot #12 on site #3 at version 0` |

Use the IDs and record versions from your own workspace. Recording approval requires evidence that the customer approved that quote. The action creates an order awaiting payment. Canceling a local publication slot follows the calendar's operator and version checks. For a submission that has already started, reconcile it through the publishing calendar.

Use the order status command to follow a queued installation. It reports the latest installation state recorded by the existing Commerce worker.

### Review platform coverage

Open **Software Library → Code map → Platform coverage** to search the loaded host and engine controller routes. Download JSON for the complete matching list. A bound route has an explicit reviewed capability. A partial route has a capability for part of the workflow. A browser handoff links to the existing workflow, which applies its own session and authorization requirements. An unmapped route needs a review before it can count toward execution coverage. The inventory shows installed routing and binding evidence. Live acceptance is tracked through execution receipts.

Try `/code sign-in`, `/code merchant payout`, or `/code action status` for account security, payout setup, and execution diagnostics. Enter authentication factors and payout account details in the existing secure forms.

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

## Taught conversational phrases

Administrators can import the installed manuals and teach typed phrases through [Manuals & Language](manual_learning.md). For example, an activated project phrase accepts `Could you please make a studio project called Launch Night`. Missing inputs appear in a task form in chat; `Every 60 minutes, run worker 12` uses the existing agent scheduler. Review receipts for actual execution and the coverage report for unsupported adapters or input contracts.
