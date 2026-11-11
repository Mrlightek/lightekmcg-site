# Query and manage application data

Administrators can enter model expressions directly in the same input used for platform commands. The `/rails` and `/console` prefixes also work. They use the same action ledger, permissions and execution receipts.

Administrators can use the Ruby-style model console. It parses supported expressions; it does not evaluate arbitrary Ruby.

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
