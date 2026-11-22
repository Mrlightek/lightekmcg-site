#!/usr/bin/env python3
"""Switch two prepared PostgreSQL databases while their clients are offline."""

import argparse
import json
import os
import re
import stat
import subprocess


IDENTIFIER = re.compile(r"[a-z][a-z0-9_]{0,62}")
RESERVED = {"postgres", "template0", "template1"}


def database_name(value):
    if not IDENTIFIER.fullmatch(value) or value in RESERVED:
        raise argparse.ArgumentTypeError("Use a non-template PostgreSQL database name")
    return value


def database_oid(value):
    if not re.fullmatch(r"[1-9][0-9]{0,9}", value) or int(value) > 2**32 - 1:
        raise argparse.ArgumentTypeError("Use the PostgreSQL OID from inspection")
    return int(value)


def snapshot(names):
    targets = ", ".join(f"'{name}'" for name in names)
    return f"""
        SELECT json_build_object('cluster_id', (SELECT system_identifier::text FROM pg_control_system()),
          'databases', coalesce(json_object_agg(datname, json_build_object(
            'oid', oid::bigint, 'owner', pg_get_userbyid(datdba), 'allows_connections', datallowconn,
            'sessions', (SELECT count(*) FROM pg_stat_activity WHERE datid = pg_database.oid)
          )), '{{}}'::json)) FROM pg_database WHERE datname IN ({targets});
    """


def mutation_sql(args):
    live, candidate, retained = args.live, args.candidate, args.retained
    original, replacement = args.original_oid, args.replacement_oid
    before = f"""live_oid = '{original}'::oid AND candidate_oid = '{replacement}'::oid AND retained_oid IS NULL"""
    after = f"""live_oid = '{replacement}'::oid AND candidate_oid IS NULL AND retained_oid = '{original}'::oid"""
    if args.action == "promote":
        expected, done, other = before, after, candidate
        changes = f'ALTER DATABASE "{live}" RENAME TO "{retained}"; ALTER DATABASE "{candidate}" RENAME TO "{live}";'
    elif args.action == "reverse":
        expected, done, other = after, before, retained
        changes = f'ALTER DATABASE "{live}" RENAME TO "{candidate}"; ALTER DATABASE "{retained}" RENAME TO "{live}";'
    else:
        expected, done, other = (before, "false", candidate) if args.phase == "original" else (after, "false", retained)
        changes = (f'ALTER DATABASE "{live}" ALLOW_CONNECTIONS false; ALTER DATABASE "{other}" ALLOW_CONNECTIONS false;'
                   if args.action == "fence" else f'ALTER DATABASE "{live}" ALLOW_CONNECTIONS true;')
        if args.action == "open":
            done = f"""({expected}) AND
                (SELECT datallowconn FROM pg_database WHERE datname = '{live}') AND
                NOT (SELECT datallowconn FROM pg_database WHERE datname = '{other}')"""

    fence_required = (args.action != "fence")
    return f"""
        BEGIN;
        SET LOCAL lock_timeout = '5s';
        SET LOCAL statement_timeout = '30s';
        SELECT pg_advisory_xact_lock(hashtext('lightek-database-cutover'), hashtext('{live}'));
        DO $cutover$
        DECLARE live_oid oid; candidate_oid oid; retained_oid oid;
        BEGIN
          IF (SELECT system_identifier::text FROM pg_control_system()) <> '{args.cluster_id}'
            THEN RAISE EXCEPTION 'PostgreSQL cluster identity changed'; END IF;
          SELECT oid INTO live_oid FROM pg_database WHERE datname = '{live}';
          SELECT oid INTO candidate_oid FROM pg_database WHERE datname = '{candidate}';
          SELECT oid INTO retained_oid FROM pg_database WHERE datname = '{retained}';
          IF ({done}) IS TRUE THEN RETURN; END IF;
          IF ({expected}) IS NOT TRUE THEN RAISE EXCEPTION 'Database identities changed'; END IF;
          IF EXISTS (SELECT 1 FROM pg_prepared_xacts WHERE database IN ('{live}', '{other}'))
             OR EXISTS (SELECT 1 FROM pg_stat_activity WHERE datname IN ('{live}', '{other}')) THEN
            RAISE EXCEPTION 'Stop database clients and resolve prepared transactions before switching';
          END IF;
          IF {str(fence_required).lower()} AND EXISTS (
            SELECT 1 FROM pg_database WHERE datname IN ('{live}', '{other}') AND datallowconn
          ) THEN RAISE EXCEPTION 'Fence both databases before switching or reopening the live database'; END IF;
          {changes}
        END $cutover$;
        COMMIT;
        {snapshot((live, candidate, retained))}
    """


def query(database, sql):
    output = subprocess.run(
        ["psql", "-XqAt", "--no-password", "--set", "ON_ERROR_STOP=1", "--dbname", database],
        input=sql, capture_output=True, text=True, timeout=45, check=True,
        env={**os.environ, "PGCONNECT_TIMEOUT": "5"},
    )
    return json.loads(output.stdout.splitlines()[-1])


def verify_candidate(live, candidate):
    schema = """
        SET statement_timeout = '20s';
        SELECT json_build_object('oid', (SELECT oid::bigint FROM pg_database WHERE datname = current_database()),
          'cluster_id', (SELECT system_identifier::text FROM pg_control_system()),
          'owner', (SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = current_database()),
          'migration_count', count(*), 'schema_fingerprint', md5(string_agg(version, ',' ORDER BY version)),
          'users_table', to_regclass('public.users') IS NOT NULL)
        FROM public.schema_migrations;
    """
    original, replacement = query(live, schema), query(candidate, schema)
    if not (original["cluster_id"] == replacement["cluster_id"] and original["owner"] == replacement["owner"] and original["users_table"] and
            replacement["users_table"] and original["migration_count"] > 0 and
            original["schema_fingerprint"] == replacement["schema_fingerprint"]):
        raise ValueError("Candidate application schema does not match the live release")
    return {"cluster_id": original["cluster_id"], "database_owner": original["owner"],
            "original_oid": original["oid"], "replacement_oid": replacement["oid"],
            "schema_fingerprint": original["schema_fingerprint"]}


def prepare_candidate(args):
    inventory = query("postgres", snapshot((args.live, args.candidate, args.retained)))
    mapping = inventory["databases"]
    live, candidate = mapping.get(args.live, {}), mapping.get(args.candidate, {})
    if (inventory["cluster_id"] != args.cluster_id or live.get("oid") != args.original_oid or
            candidate.get("oid") != args.replacement_oid or args.retained in mapping or live.get("owner") != candidate.get("owner")):
        raise ValueError("The live and candidate identities do not match the preparation request")
    target = query(args.candidate, """
        SELECT json_build_object('oid', (SELECT oid::bigint FROM pg_database WHERE datname = current_database()),
          'empty', NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname !~ '^pg_' AND n.nspname <> 'information_schema')
          AND NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname !~ '^pg_' AND nspname NOT IN ('public', 'information_schema')));
    """)
    if target["oid"] != args.replacement_oid or not target["empty"]:
        raise ValueError("Restore into the empty candidate database recorded in the request")
    descriptor = os.open(args.archive, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb", buffering=0) as archive:
        if not stat.S_ISREG(os.fstat(archive.fileno()).st_mode) or archive.read(5) != b"PGDMP":
            raise ValueError("Supply an approved PostgreSQL custom-format archive")
        archive.seek(0)
        subprocess.run(["pg_restore", "--no-password", "--single-transaction", "--exit-on-error", "--no-owner",
                        "--no-acl", "--role", candidate["owner"], "--dbname", args.candidate], stdin=archive, capture_output=True,
                       text=True, timeout=1800, check=True, env={**os.environ, "PGCONNECT_TIMEOUT": "5"})
    proof = verify_candidate(args.live, args.candidate)
    if (proof["cluster_id"] != args.cluster_id or proof["original_oid"] != args.original_oid or
            proof["replacement_oid"] != args.replacement_oid):
        raise ValueError("Database identities changed during preparation; inspect before continuing")
    return proof


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "prepare", "verify", "fence", "promote", "reverse", "open"))
    for name in ("live", "candidate", "retained"):
        parser.add_argument(f"--{name}", required=True, type=database_name)
    parser.add_argument("--original-oid", type=database_oid)
    parser.add_argument("--replacement-oid", type=database_oid)
    parser.add_argument("--cluster-id")
    parser.add_argument("--phase", choices=("original", "replacement"))
    parser.add_argument("--confirm")
    parser.add_argument("--archive")
    args = parser.parse_args()
    names = (args.live, args.candidate, args.retained)
    if len(set(names)) != 3:
        parser.error("The live, candidate and retained names must be distinct")
    if any(not name.startswith(args.live + "_") for name in names[1:]):
        parser.error("Name the candidate and retained databases with the live database prefix")
    if args.action not in ("inspect", "verify"):
        if not args.original_oid or not args.replacement_oid or args.original_oid == args.replacement_oid:
            parser.error("Supply both distinct database OIDs from inspection")
        if not re.fullmatch(r"[1-9][0-9]{0,19}", args.cluster_id or ""):
            parser.error("Supply the PostgreSQL cluster ID from inspection")
        if args.action == "prepare":
            if args.confirm != args.candidate or not args.archive:
                parser.error("Confirm the candidate name and specify the approved backup archive")
        elif args.confirm != args.live:
            parser.error("Confirm the live database name")
        if args.action in ("fence", "open") and not args.phase:
            parser.error("Select which database should be under the live name")
    try:
        if args.action == "prepare":
            print(json.dumps({"action": args.action, **prepare_candidate(args)}))
        elif args.action == "verify":
            print(json.dumps({"action": args.action, **verify_candidate(args.live, args.candidate)}))
        else:
            sql = snapshot(names) if args.action == "inspect" else mutation_sql(args)
            print(json.dumps({"action": args.action, **query("postgres", sql)}))
    except subprocess.CalledProcessError as error:
        parser.exit(1, error.stderr)
    except ValueError as error:
        parser.exit(1, f"{error}\n")
    except OSError as error:
        parser.exit(1, f"Could not open a local archive or PostgreSQL client ({error.__class__.__name__}).\n")
    except subprocess.TimeoutExpired:
        parser.exit(1, "Database result is uncertain. Inspect both OIDs before continuing.\n")


if __name__ == "__main__":
    main()
