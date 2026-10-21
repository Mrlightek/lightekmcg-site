# Nevaeh CLI (Phase 7A.8A)

The local entrypoint is `bin/nevaeh`. The foundation uses only Ruby's standard library and does **not** load Rails, connect to a database, contact GitHub, dispatch jobs, modify files, or authorize capability execution.

## Commands

| Command | Description |
| --- | --- |
| `bin/nevaeh help` | List supported commands and usage |
| `bin/nevaeh version` | Show CLI implementation version |
| `bin/nevaeh doctor` | Show foundation availability (not a production health check) |
| `bin/nevaeh capabilities` | Show CLI command availability; does **not** enumerate Rails capability records |

Use `--format json` before the command for machine-readable success results, e.g. `bin/nevaeh --format json doctor`. Successful operations exit `0`; invalid usage exits `2`. JSON error reporting is supported when the `--format json` option was parsed successfully.

## Execution contract

This release has no mutating CLI subcommands and no authenticated API transport. Future ticket/generator commands must invoke the **same Rails service contracts** as the UI/API and enforce Gatekeeper independently at the service/execution boundary; a CLI prompt or `--dry-run` must not confer authorization. Generated file changes must remain isolated until separately approved for promotion.

## Acceptance standard for future commands

Each new command must include usage help, examples, structured JSON output where applicable, successful and rejected-path automated tests, audit identity and correlation data when applicable, and the same authorization policy as its API/UI counterpart.

## YAML Capability Configuration (7A.8B)

`bin/nevaeh config list`, `config show KEY`, `config validate KEY`, `config create KEY [--write]`, and `config job-add KEY ID SERVICE [--after PREVIOUS_JOB] [--write]` are available. Config creation is a dry run unless `--write` is supplied. All capabilities remain disabled. See [Nevaeh YAML Capabilities](nevaeh_yaml_capabilities.md).
