#!/usr/bin/env python3
"""Guard a same-host cutover between two already prepared production slots."""
import argparse
import fcntl
import http.client
import json
import os
from pathlib import Path
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lightek_cable_setup import handshake


DOMAIN = "lightekmcg.com"
SLOTS = {"blue": (28100, 28101), "green": (28200, 28201)}
SHA = re.compile(r"[0-9a-f]{40}")
STATE_DIR = Path("/var/lib/lightek/blue-green")
SLOT_ROOT = Path("/var/www/lightekmcg-slots")


class CutoverError(RuntimeError):
    pass


def command(*args):
    subprocess.run(args, check=True, timeout=120)


def worker_unit(slot):
    return f"lightek-production-worker@{slot}.service"


def worker_state(slot):
    result = subprocess.run(
        ["systemctl", "show", "--property=ActiveState", "--value", worker_unit(slot)],
        check=True, capture_output=True, text=True, timeout=10,
    )
    return result.stdout.strip()


def check_worker(slot, sha):
    command("runuser", "-u", "lightek", "--", "/bin/bash", "-c",
        'set -ae; source /etc/lightek/lightekmcg-site.env; set +a; '
        'exec /usr/local/lib/lightek/run_production_slot.sh verify-worker "$1" "$2"',
        "slot-readiness", slot, sha)


def probe_http(port, path, *, edge=False):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    try:
        if edge:
            with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
                connection.sock = ssl.create_default_context().wrap_socket(sock, server_hostname=DOMAIN)
                return read_http(connection, path)
        return read_http(connection, path)
    finally:
        connection.close()


def read_http(connection, path):
    connection.request("GET", path, headers={
        "Host": DOMAIN, "X-Forwarded-Proto": "https", "Cache-Control": "no-cache",
    })
    response = connection.getresponse()
    if response.status != 200:
        raise CutoverError(f"{path} returned HTTP {response.status}")
    return response.read(4096) if path == "/__lightek/release" else b""


def prove_web(slot, sha, *, edge=False):
    web, cable = SLOTS[slot]
    port = 443 if edge else web
    last_error = None
    for _ in range(5):
        try:
            probe_http(port, "/up", edge=edge)
            payload = json.loads(probe_http(port, "/__lightek/release", edge=edge))
            if payload.get("component") != "lightek_app" or payload.get("source_sha") != sha:
                raise CutoverError("Served revision does not match the approved SHA")
            handshake("127.0.0.1", 443 if edge else cable, DOMAIN, tls=edge)
            return
        except (OSError, ValueError, http.client.HTTPException, RuntimeError) as error:
            last_error = error
            time.sleep(2)
    raise CutoverError(f"{slot} {'edge' if edge else 'local'} verification failed: {last_error}")


def route(slot, sha):
    web, cable = SLOTS[slot]
    return (
        f"# lightek-blue-green {slot} {sha}\n"
        "PassengerEnabled off\n"
        "ProxyPreserveHost On\n"
        "RequestHeader set X-Forwarded-Proto https\n"
        f'ProxyPass "/cable" "http://127.0.0.1:{cable}/cable" upgrade=websocket timeout=7200\n'
        f'ProxyPassReverse "/cable" "http://127.0.0.1:{cable}/cable"\n'
        f'ProxyPass "/" "http://127.0.0.1:{web}/"\n'
        f'ProxyPassReverse "/" "http://127.0.0.1:{web}/"\n'
    )


def read_route(path):
    content = path.read_text()
    fields = content.partition("\n")[0].removeprefix("# ").split()
    if len(fields) != 3:
        raise CutoverError("Routing include is not a valid managed slot")
    marker, slot, sha = fields
    if marker != "lightek-blue-green" or slot not in SLOTS or not SHA.fullmatch(sha) or content != route(slot, sha):
        raise CutoverError("Routing include is not a valid managed slot")
    return slot, sha


def atomic_write(path, content):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}-")
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def reload_edge():
    command("apache2ctl", "configtest")
    command("systemctl", "reload", "apache2")


def capacity(inactive_mib, reserve_mib, storage_path):
    memory = {}
    for line in Path("/proc/meminfo").read_text().splitlines():
        key, value = line.split(":", 1)
        memory[key] = int(value.split()[0])
    available = memory["MemAvailable"] // 1024
    return {
        "memory_available_mib": available,
        "memory_total_mib": memory["MemTotal"] // 1024,
        "swap_used_mib": (memory["SwapTotal"] - memory["SwapFree"]) // 1024,
        "free_disk_mib": shutil.disk_usage(storage_path).free // (1024 * 1024),
        "inactive_slot_budget_mib": inactive_mib,
        "host_reserve_mib": reserve_mib,
        "memory_budget_fits": available >= inactive_mib + reserve_mib,
    }


def prove_same_schema(slot, sha, current_sha):
    checkout = SLOT_ROOT / slot
    actual = subprocess.check_output(
        ["runuser", "-u", "lightek", "--", "git", "-C", str(checkout), "rev-parse", "HEAD"],
        text=True, timeout=10,
    ).strip()
    if actual != sha:
        raise CutoverError("Inactive checkout does not match the reviewed SHA")
    result = subprocess.run(["runuser", "-u", "lightek", "--", "git", "-C", str(checkout),
        "diff", "--quiet", current_sha, sha, "--", "db/migrate", "db/schema.rb", "db/structure.sql"], timeout=15)
    if result.returncode != 0:
        raise CutoverError("Could not verify an unchanged schema; keep the active slot in service")


def prepare(include, journal, slot, sha, inactive_mib, reserve_mib):
    if journal.exists():
        raise CutoverError("An interrupted cutover needs recovery")
    active, current_sha = read_route(include)
    if active == slot or worker_state(slot) != "inactive":
        raise CutoverError("Choose the inactive slot with its worker stopped")
    prove_same_schema(slot, sha, current_sha)
    info = capacity(inactive_mib, reserve_mib, SLOT_ROOT)
    if not info["memory_budget_fits"]:
        raise CutoverError("Insufficient host headroom for the inactive slot")
    web = f"lightek-production-web@{slot}.service"
    cable = f"lightek-production-cable@{slot}.service"
    command("systemctl", "start", f"lightek-slot-{slot}.slice")
    command("systemctl", "set-property", "--runtime", f"lightek-slot-{slot}.slice",
        f"MemoryMax={inactive_mib}M", "MemorySwapMax=0")
    try:
        command("systemctl", "start", web, cable)
        prove_web(slot, sha)
        prove_web(active, current_sha, edge=True)
    except (Exception, KeyboardInterrupt):
        command("systemctl", "stop", web, cable)
        raise


def restore(include, journal):
    previous, previous_sha = read_route(journal)
    other = next(slot for slot in SLOTS if slot != previous)
    atomic_write(include, route(previous, previous_sha))
    try:
        reload_edge()
    finally:
        restore_worker(previous, previous_sha, other)
    prove_web(previous, previous_sha, edge=True)
    journal.unlink()
    sync_directory(journal.parent)


def restore_worker(previous, previous_sha, other):
    command("systemctl", "stop", worker_unit(other))
    if worker_state(other) != "inactive":
        raise CutoverError("Could not stop the other worker; rollback journal retained")
    if worker_state(previous) != "active":
        command("systemctl", "start", worker_unit(previous))
    check_worker(previous, previous_sha)


def switch(include, journal, slot, sha, expected_active):
    if journal.exists():
        raise CutoverError("An interrupted cutover needs recovery before another switch")
    previous, previous_sha = read_route(include)
    if previous == slot or previous_sha != expected_active:
        raise CutoverError("Active slot or expected active revision changed")
    if worker_state(previous) != "active" or worker_state(slot) != "inactive":
        raise CutoverError("Expected exactly one active worker in the current slot")

    prove_same_schema(slot, sha, previous_sha)
    prove_web(previous, previous_sha, edge=True)
    check_worker(previous, previous_sha)
    prove_web(slot, sha)
    atomic_write(journal, route(previous, previous_sha))
    try:
        command("systemctl", "stop", worker_unit(previous))
        if worker_state(previous) != "inactive":
            raise CutoverError("Previous worker did not drain")
        command("systemctl", "start", worker_unit(slot))
        check_worker(slot, sha)
        atomic_write(include, route(slot, sha))
        reload_edge()
        prove_web(slot, sha, edge=True)
    except (Exception, KeyboardInterrupt):
        restore(include, journal)
        raise
    journal.unlink()
    sync_directory(journal.parent)


def start_active_slot(include, journal):
    if journal.exists():
        raise CutoverError("An interrupted cutover needs recovery before starting a slot")
    slot, sha = read_route(include)
    other = next(color for color in SLOTS if color != slot)
    if worker_state(other) != "inactive":
        raise CutoverError("Inactive slot worker is already running")
    command("systemctl", "start", f"lightek-production-web@{slot}.service",
        f"lightek-production-cable@{slot}.service")
    prove_web(slot, sha)
    command("systemctl", "start", worker_unit(slot))
    check_worker(slot, sha)


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("Expected a positive number of MiB")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    report = commands.add_parser("capacity")
    report.add_argument("--inactive-mib", type=positive, required=True)
    report.add_argument("--reserve-mib", type=positive, required=True)
    report.add_argument("--storage-path", type=Path, default=Path("/var/www"))
    promote = commands.add_parser("switch")
    promote.add_argument("--slot", choices=SLOTS, required=True)
    promote.add_argument("--sha", required=True)
    promote.add_argument("--expected-active", required=True)
    boot = commands.add_parser("prepare")
    boot.add_argument("--slot", choices=SLOTS, required=True)
    boot.add_argument("--sha", required=True)
    boot.add_argument("--inactive-mib", type=positive, required=True)
    boot.add_argument("--reserve-mib", type=positive, required=True)
    commands.add_parser("recover")
    commands.add_parser("start-active-slot")
    args = parser.parse_args()

    if args.action == "capacity":
        print(json.dumps(capacity(args.inactive_mib, args.reserve_mib, args.storage_path), sort_keys=True))
        return
    if os.geteuid() != 0:
        parser.error("Cutover requires a privileged operator")

    include = STATE_DIR / "active.conf"
    journal = STATE_DIR / "rollback.conf"
    with (STATE_DIR / "cutover.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.action == "recover":
            restore(include, journal)
            print("Previous release restored and verified")
        elif args.action == "start-active-slot":
            start_active_slot(include, journal)
        elif args.action == "prepare":
            if not SHA.fullmatch(args.sha):
                parser.error("Enter the full candidate SHA")
            prepare(include, journal, args.slot, args.sha, args.inactive_mib, args.reserve_mib)
            print(f"Inactive slot {args.slot} verified at {args.sha}")
        else:
            if not SHA.fullmatch(args.sha) or not SHA.fullmatch(args.expected_active):
                parser.error("Both revisions must be full commit SHAs")
            switch(include, journal, args.slot, args.sha, args.expected_active)
            print(f"Active slot {args.slot} verified at {args.sha}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
