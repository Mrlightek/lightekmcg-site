# Query and manage application data

Administrators can enter model expressions directly in the same input used for platform commands. The `/rails` and `/console` prefixes also work. They use the same action ledger, permissions and execution receipts.

Administrators can use the Ruby-style model console. It parses supported expressions; it does not evaluate arbitrary Ruby.

## Use plain English

Type or say a command in Nevaeh. Use **record** or **records** to identify a model command. Use a model's full name from **List installed models** if a name is ambiguous.

| Task | Example |
| --- | --- |
| Discover models | `List installed models` |
| Inspect fields and types | `Show the fields for user records` |
| List, filter, sort and limit | `List user records where role is client ordered by id descending limit 10` |
| Count matching records | `How many user records where role is client?` |
| Inspect one record | `Find user record 123` |
| Get the first or last match | `Show the first user record ordered by id ascending` |
| Find one match by field | `Find user record where role is client` |
| Check whether a match exists | `Check for any user records where role is client` |
| Return selected columns | `List user records return only id, role ordered by id ascending limit 20 skip 20` |
| Return distinct values | `List distinct user records return only role` |
| Calculate a numeric value | `List user records calculate maximum of id where role is client` |
| Create a record | `Create Example records with title to "Opening Night"` |
| Update a record | `Update Example record 123 set title to "New title"` |
| Delete a record | `Delete Example record 123` |

Replace `Example`, its fields and record IDs with ordinary models and records you can manage. Use `and` between field conditions or assignments. Quote text containing spaces. Filters and edits accept literal text, numbers, booleans, null and scalar lists subject to the model field rules. Create and update also accept a JSON object after `with`.

Both forms use the same model lookup, permissions, validations, redaction, Dispatch and receipts. In Decide or Reflect, record operations produce a preview. Use `/capabilities` or the Guide for workflows that use domain services. For example, refunding an order is a Commerce operation with a payment workflow.

For Ruby queries, use `find_by`, `exists?`, `pluck`, `ids`, `distinct`, `offset`, `sum`, `average`, `minimum`, and `maximum`. Calculations take a numeric column, and projection and filter fields use the same checks as other console commands.

## Discover models and fields

```text
/models
/schema User
User.count
/rails User.where(role: "client").order(id: :desc).limit(10)
```

Results are scoped by current CanCan permissions. Collections return at most 100 records. Credentials are not an export interface; secret fields are redacted and credential records use their dedicated service.

## Inspect a record

```text
/rails User.find(123)
```

Replace 123 with a real ID returned by an authorized query. Only literal field hashes are accepted for filters. Raw SQL, connection methods, blocks, interpolation and arbitrary methods are rejected.

## Edit ordinary model records

Supported model operations include create!, find(...).update! and find(...).destroy!, with ordinary validations and callbacks. Prefer the named resource or domain capability when available:

```text
/read agents
/update agents AGENT_ID {"instructions":"Give concise, practical answers."}
```

Financial, infrastructure, Studio, authentication and orchestration state use domain services instead of raw writes. The console reports this boundary. Only super_admin can change account authority; an administrator cannot promote an account into host control through the console.

Use /describe for the relevant operation and read its receipt. A failed validation leaves the local write unapplied. Host effects from external operations do not have database rollback semantics.
