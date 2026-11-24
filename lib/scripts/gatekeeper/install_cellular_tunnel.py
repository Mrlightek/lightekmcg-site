#!/usr/bin/env python3
import base64
import ipaddress
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

INTERFACE = "lt-cellular"
UNIT = f"wg-quick@{INTERFACE}"
PATH = "/usr/sbin:/usr/bin:/sbin:/bin"


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=180,
                          env={"PATH": PATH, "DEBIAN_FRONTEND": "noninteractive"}).stdout


def atomic_write(path, content):
    with tempfile.NamedTemporaryFile(dir=path.parent, mode="w", delete=False) as handle:
        handle.write(content)
        temporary = handle.name
    os.replace(temporary, path)


def main(payload):
    peer = str(ipaddress.IPv4Address(payload["peer_ip"]))
    cidr = str(ipaddress.IPv4Network(payload["sim_cidr"]))
    endpoint = payload["endpoint"]
    host, separator, port = endpoint.rpartition(":")
    if separator != ":" or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}", host) or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError("Invalid Hub endpoint")
    if any(not re.fullmatch(r"[A-Za-z0-9+/]{43}=", payload[key]) or
           len(base64.b64decode(payload[key], validate=True)) != 32 for key in ("private_key", "hub_public_key")):
        raise ValueError("Invalid WireGuard key")

    if not Path("/usr/bin/wg-quick").exists() or not Path("/usr/sbin/nft").exists():
        run("apt-get", "-q", "update")
        run("apt-get", "-q", "-y", "install", "--no-install-recommends", "wireguard-tools", "nftables")

    routes = json.loads(run("ip", "-j", "-4", "route", "show", "default"))
    if len(routes) != 1 or not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,15}", routes[0].get("dev", "")):
        raise ValueError("Expected one customer WAN interface")
    wan = routes[0]["dev"]
    directory = Path("/etc/wireguard")
    directory.mkdir(mode=0o700, exist_ok=True)
    conf = directory / f"{INTERFACE}.conf"
    nft = directory / f"{INTERFACE}.nft"
    nft_config = f"""
add table inet lightek_cellular
delete table inet lightek_cellular
table inet lightek_cellular {{
  chain input {{
    type filter hook input priority -10; policy accept;
    iifname "{INTERFACE}" drop
  }}
  chain forward {{
    type filter hook forward priority -10; policy accept;
    iifname "{INTERFACE}" ip daddr {{ 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }} drop
    iifname "{INTERFACE}" oifname "{wan}" ip saddr {cidr} accept
    iifname "{INTERFACE}" drop
    iifname "{wan}" oifname "{INTERFACE}" ip daddr {cidr} ct state established,related accept
    oifname "{INTERFACE}" drop
  }}
  chain postrouting {{
    type nat hook postrouting priority srcnat; policy accept;
    iifname "{INTERFACE}" oifname "{wan}" ip saddr {cidr} masquerade
  }}
}}
"""
    config = f"""[Interface]
PrivateKey = {payload["private_key"]}
Address = {peer}/32
PostUp = /usr/sbin/sysctl -qw net.ipv4.conf.%i.rp_filter=2
PostUp = /usr/sbin/nft -f {nft}
PostDown = /usr/sbin/nft delete table inet lightek_cellular

[Peer]
PublicKey = {payload["hub_public_key"]}
Endpoint = {endpoint}
AllowedIPs = {cidr}
PersistentKeepalive = 25
"""
    if conf.exists() and (conf.read_text() != config or not nft.exists() or nft.read_text() != nft_config):
        raise ValueError("The customer VPS already has another cellular tunnel")
    atomic_write(nft, nft_config)
    atomic_write(conf, config)
    Path("/etc/sysctl.d/99-lightek-cellular.conf").write_text("net.ipv4.ip_forward=1\n")
    run("sysctl", "-qw", "net.ipv4.ip_forward=1")
    run("systemctl", "enable", "--now", UNIT)
    for _ in range(12):
        line = run("wg", "show", INTERFACE, "latest-handshakes").strip().split()
        if len(line) == 2 and line[0] == payload["hub_public_key"] and 0 <= time.time() - int(line[1]) <= 180:
            print(json.dumps({"status": "ready", "peer_ip": peer}))
            return
        time.sleep(5)
    raise ValueError("The customer WireGuard peer has not completed a handshake")


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main(json.load(sys.stdin))
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
