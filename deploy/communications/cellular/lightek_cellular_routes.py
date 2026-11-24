import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


STATE = Path("/var/lib/lightek-cellular/routes.json")
CONFIG = Path("/etc/lightek-cellular/hub.json")
EGRESS_PRIORITY = 1000
BLOCK_PRIORITY = 1001


def run(*args, stdin=None):
    return subprocess.run(
        args, input=stdin, encoding="utf-8", check=True, stdout=subprocess.PIPE,
        timeout=10, env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin"}
    ).stdout


def rules():
    return json.loads(run("ip", "-j", "-4", "rule", "show"))


def peer_interface(peer, carrier):
    routes = json.loads(run("ip", "-j", "-4", "route", "show", "table", "main", "exact", f"{peer}/32"))
    if len(routes) != 1 or routes[0].get("gateway") or not routes[0].get("dev"):
        raise ValueError("The customer peer requires one direct /32 route in main")
    device = routes[0]["dev"]
    if device == carrier or not re.fullmatch(r"wg-c[a-zA-Z0-9_-]{1,11}", device):
        raise ValueError("The customer requires a dedicated wg-c WireGuard interface")
    allowed = [line.split() for line in run("wg", "show", device, "allowed-ips").splitlines()]
    if len(allowed) != 1 or "0.0.0.0/0" not in allowed[0][1:]:
        raise ValueError("The customer interface requires its own WireGuard peer with AllowedIPs 0.0.0.0/0")
    return device


def firewall(carrier, subnet, rows):
    elements = ", ".join(f'"{row["device"]}" . {ip}' for ip, row in sorted(rows.items()))
    members = f"elements = {{ {elements} }};" if elements else ""
    run("nft", "-f", "-", stdin=f'''
add table inet lightek_cellular
delete table inet lightek_cellular
table inet lightek_cellular {{
  set routes {{ type ifname . ipv4_addr; {members} }}
  chain input {{
    type filter hook input priority -10; policy accept;
    iifname "{carrier}" drop
    iifname "wg-c*" drop
  }}
  chain forward {{
    type filter hook forward priority -10; policy accept;
    iifname "{carrier}" ip daddr {subnet} drop
    iifname "{carrier}" oifname . ip saddr @routes accept
    iifname "{carrier}" drop
    iifname . ip daddr @routes oifname "{carrier}" ct state established,related accept
    iifname "wg-c*" drop
    oifname "{carrier}" drop
    oifname "wg-c*" drop
  }}
}}
''')


def setup_guard(carrier, subnet, rows):
    run("wg", "show", carrier, "public-key")
    firewall(carrier, subnet, rows)
    existing = [rule for rule in rules() if rule.get("priority") == BLOCK_PRIORITY]
    if not existing:
        run("ip", "-4", "rule", "add", "pref", str(BLOCK_PRIORITY), "iif", carrier, "unreachable")
    elif existing != [{"priority": BLOCK_PRIORITY, "src": "all", "iif": carrier, "action": "unreachable"}]:
        same = len(existing) == 1 and existing[0].get("iif") == carrier and \
            existing[0].get("type", existing[0].get("action")) == "unreachable" and existing[0].get("src", "all") == "all"
        if not same:
            raise ValueError("The cellular guard routing priority is already in use")
    run("ip", "-4", "route", "replace", str(subnet), "dev", carrier, "scope", "link")


def apply(carrier, ip, row):
    table = str(row["table"])
    run("ip", "-4", "route", "replace", "default", "via", row["peer"], "dev", row["device"], "onlink", "table", table)
    same_source = [rule for rule in rules() if rule.get("priority") == EGRESS_PRIORITY and
                   rule.get("iif") == carrier and rule.get("src") in (ip, f"{ip}/32")]
    if not same_source:
        run("ip", "-4", "rule", "add", "pref", str(EGRESS_PRIORITY), "iif", carrier, "from", f"{ip}/32", "lookup", table)
    elif len(same_source) != 1 or str(same_source[0].get("table")) != table:
        raise ValueError("The SIM source already routes to another table")


def save(rows):
    with tempfile.NamedTemporaryFile(dir=STATE.parent, mode="w", delete=False) as handle:
        json.dump(rows, handle)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(handle.name, STATE)
    fd = os.open(STATE.parent, os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def main(args):
    os.umask(0o077)
    cfg = json.loads(CONFIG.read_text())
    carrier = cfg["carrier_interface"]
    if not re.fullmatch(r"wg-[A-Za-z0-9_-]{1,12}", carrier) or carrier.startswith("wg-c"):
        raise ValueError("Invalid carrier interface")
    subnet = ipaddress.IPv4Network(cfg["sim_ipv4_cidr"])
    STATE.parent.mkdir(mode=0o700, exist_ok=True)
    with (STATE.parent / "routes.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        rows = json.loads(STATE.read_text()) if STATE.exists() else {}
        if args == ["--restore"]:
            setup_guard(carrier, subnet, {})
            for ip, row in rows.items():
                if peer_interface(row["peer"], carrier) != row["device"]:
                    raise ValueError("The customer WireGuard interface changed")
                apply(carrier, ip, row)
            firewall(carrier, subnet, rows)
            return

        if len(args) == 2 and args[0] in ("--check", "--check-connected"):
            device = peer_interface(str(ipaddress.IPv4Address(args[1])), carrier)
            if args[0] == "--check-connected":
                handshakes = run("wg", "show", device, "latest-handshakes").splitlines()
                if len(handshakes) != 1 or not 0 <= time.time() - int(handshakes[0].split()[-1]) <= 180:
                    raise ValueError("No recent authenticated customer handshake")
            setup_guard(carrier, subnet, rows)
            return
        if len(args) != 3:
            raise ValueError("Expected SIM IP, customer peer IP and routing table")
        ip, peer = map(ipaddress.IPv4Address, args[:2])
        table = int(args[2])
        if ip not in subnet or ip in (subnet.network_address, subnet.broadcast_address) or peer in subnet \
                or table < 100 or table > 2147483647 or table in (253, 254, 255):
            raise ValueError("SIM subnet, peer or table is invalid")
        key = str(ip)
        row = {"peer": str(peer), "device": peer_interface(str(peer), carrier), "table": table}
        if (key in rows and rows[key] != row) or any(
            previous["table"] == table and source != key for source, previous in rows.items()
        ):
            raise ValueError("SIM or routing table already belongs to another line")
        setup_guard(carrier, subnet, rows)
        apply(carrier, key, row)
        rows[key] = row
        save(rows)
        firewall(carrier, subnet, rows)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as error:
        sys.exit(f"Cellular route update failed: {error}")
