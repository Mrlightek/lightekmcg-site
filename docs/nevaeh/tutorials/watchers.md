# Watch changes and respond automatically

Watchers periodically observe a source, compare it with a saved baseline and react only to matching changes. They use the existing minute sweep and agent/Dispatch execution pipeline. Host watcher administration requires super_admin.

## Watch a package without automatically installing it

```text
/watch create {"name":"FFmpeg updates","agent":"warden","kind":"ubuntu_package","target":{"package":"ffmpeg","refresh":true},"condition":"updated","response":"prepare","interval_minutes":60}
/watch list
/watch poll WATCHER_ID
/watch show WATCHER_ID
```

Replace WATCHER_ID with the created ID. The first successful observation establishes a baseline and triggers no installations. A later version change creates an event and installation plan. `refresh:true` refreshes APT indexes before observing.

Inspect the event's dependency/download/disk plan. To apply the prepared package response:

```text
/watch apply EVENT_ID
```

Apply dispatches a real agent run. Watch its receipt; prepared or dispatched is not proof of installation.

## Automatically update a chosen package

Use the same definition with `response:"update"`. This explicitly authorizes the selected package's setup workflow when a changed Ubuntu candidate is detected. It is not a whole-system upgrade. Current owner permissions, agent assignments and trusted-package rules still apply.

## Detect newly available applications

```text
/watch create {"name":"New video packages","kind":"ubuntu_catalog","target":{"query":"video","refresh":true},"condition":"new","response":"prepare","interval_minutes":120}
```

Catalog queries must fit the 1000-entity snapshot budget; broad queries fail rather than silently missing entries. Narrow the query if needed. Each newly observed package gets a plan; unknown application functions remain adapter drafts.

## Observe configured APT source changes

```text
/watch create {"name":"Repository sources","kind":"ubuntu_sources","target":{},"condition":"new_or_updated","response":"prepare","interval_minutes":60}
```

This detects changes in the host's configured .list/.sources files. It does not discover arbitrary repositories across the Internet or enable a new source automatically. URL user information, query strings and fragments are removed from source events. Do not use token-bearing URL paths as publicly shared event data.

## Watch a GitHub branch or new repository

```text
/watch create {"name":"Develop changes","kind":"github_repository","target":{"repository":"Mrlightek/lightekmcg-site","branch":"develop"},"condition":"updated","response":"prepare","interval_minutes":30}
/watch create {"name":"New repositories","kind":"github_account","target":{"owner":"Mrlightek","account_type":"user"},"condition":"new","response":"prepare","interval_minutes":60}
```

Use account_type organization for an organization. Public repositories work without a credential. For private access, specify a Vault credential_slug whose policy permits consumer NevaehOs::WatchSensors and purpose nevaeh_repository_watch. Never paste a token into a watcher. The selected credential determines which repositories are visible. Private user-account discovery requires a user token owned by that account; organization access uses the credential's organization permissions. An existing platform GitHub App credential may be restricted to the platform repository, so use an appropriately scoped read credential for additional repositories. Account snapshots are capped at 1000 accessible repositories.

A new GitHub repository or source produces an onboarding packet: documentation, runtime/dependencies, target/configuration and acceptance checks to resolve. Applying this packet opens an onboarding ticket; it does not clone or deploy unreviewed code.

## Trigger an existing operation

Use response command with a structured command_template, for example `{"kind":"run","id":12}` to run an existing reviewed worker. Whole-value placeholders include @event.package, @event.repository, @event.branch, @event.version, @event.entity and @event.source. They are data substitutions, not shell/Ruby fragments. A native capability template needs its explicit authorized site_id and domain inputs.

## Pause, recover and edit

`/watch pause ID` stops future observations and pending reactions. `/watch resume ID` restores polling. Three consecutive sensor failures pause the watcher. Fix access/network/target errors shown in its receipt, then resume. Editing its target, condition, response or agent establishes a new baseline. Old events cannot silently adopt a changed rule. Deleted entities do not trigger installation responses.
