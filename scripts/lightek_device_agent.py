#!/usr/bin/env python3
"""Lightek opt-in cross-platform device reporting agent (Python 3 stdlib).

No remote shell, software installation, backup restoration or arbitrary commands.
Only the explicit read-only maintenance action allowlist can be processed.
"""
import ctypes
from datetime import datetime, timezone
import json
import os
import platform
import shutil
import subprocess
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def cpu_sample(interval=0.2):
    if sys.platform != "linux":
        return None
    def counters():
        with open("/proc/stat", encoding="utf-8") as source:
            values = [int(value) for value in source.readline().split()[1:]]
        return sum(values), values[3] + values[4]
    first, idle_first = counters()
    time.sleep(interval)
    second, idle_second = counters()
    return round(100 * (1 - (idle_second - idle_first) / (second - first)), 1) if second > first else None


def memory_percent():
    if sys.platform == "linux":
        with open("/proc/meminfo", encoding="utf-8") as source:
            info = dict((key.rstrip(":"), int(value.split()[0]))
                        for key, value in (line.split(":", 1) for line in source))
        return round(100 * (1 - info["MemAvailable"] / info["MemTotal"]), 1)
    if sys.platform == "darwin":
        return None  # VM statistics need a separately verified platform adapter.
    if sys.platform == "win32":
        class MemoryStatus(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("memory_load", ctypes.c_ulong),
                        ("total_phys", ctypes.c_ulonglong), ("avail_phys", ctypes.c_ulonglong),
                        ("total_page", ctypes.c_ulonglong), ("avail_page", ctypes.c_ulonglong),
                        ("total_virtual", ctypes.c_ulonglong), ("avail_virtual", ctypes.c_ulonglong),
                        ("avail_extended_virtual", ctypes.c_ulonglong)]
        status = MemoryStatus()
        status.length = ctypes.sizeof(status)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return None
        return float(status.memory_load)
    return None


def collect():
    root = os.path.abspath(os.sep)
    usage = shutil.disk_usage(root)
    metrics = {"disk_percent": round(100 * usage.used / usage.total, 1)}
    for key, reader in (("cpu_percent", cpu_sample), ("memory_percent", memory_percent)):
        try:
            value = reader()
            if value is not None:
                metrics[key] = min(100, max(0, value))
        except (OSError, ValueError, KeyError, ZeroDivisionError, AttributeError):
            pass
    return metrics


def endpoint():
    url = os.environ["LIGHTEK_DEVICE_URL"]
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or
            parsed.password or parsed.path != "/gatekeeper/device" or parsed.query or parsed.fragment):
        raise ValueError("Use an HTTPS Gatekeeper device endpoint without embedded credentials")
    return url


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Keep the device bearer token scoped to the configured Gatekeeper URL.
        return None


def post(payload):
    request = urllib.request.Request(endpoint(), data=json.dumps(payload).encode("utf-8"),
        method="POST", headers={"Content-Type": "application/json",
        "Authorization": "Bearer " + os.environ["LIGHTEK_DEVICE_TOKEN"]})
    opener = urllib.request.build_opener(
        NoRedirects(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    with opener.open(request, timeout=15) as response:
        result = json.load(response)
    if not result.get("ok"):
        raise RuntimeError("Gatekeeper rejected the request")
    return result


def _probe(argv, timeout=12):
    """Execute only fixed, local, read-only OS inspection commands."""
    try:
        completed = subprocess.run(argv, capture_output=True, text=True,
                                   timeout=timeout, check=False, shell=False)
        return completed.returncode, (completed.stdout + completed.stderr)[:400]
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def read_only_check(code):
    if code == "refresh_inventory":
        return {"status": "ok", "observation": "Platform: " + platform.system()[:80]}
    if code == "check_patch_status":
        if sys.platform == "win32":
            rc, output = _probe(["powershell.exe", "-NoProfile", "-NonInteractive",
                "-Command", "(Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1).HotFixID"])
            if rc == 0 and output.strip():
                return {"status": "warning", "observation": "Last installed hotfix: " + output.strip()[:100] +
                    "; update compliance not verified"}
        elif sys.platform == "darwin":
            rc, output = _probe(["softwareupdate", "--list"])
            if rc == 0:
                return {"status": "warning",
                        "observation": "Apple softwareupdate inventory inspected; update compliance not verified"}
        elif sys.platform == "linux" and shutil.which("apt"):
            rc, output = _probe(["apt", "list", "--upgradable"])
            if rc == 0:
                count = sum(1 for line in output.splitlines() if "[upgradable from:" in line)
                return {"status": "warning",
                        "observation": "APT lists " + str(count) + " upgradable packages; update compliance not verified"}
        return {"status": "unavailable", "observation": "Trusted patch inventory unavailable"}
    if code == "check_backup_status":
        if sys.platform == "darwin" and shutil.which("tmutil"):
            rc, output = _probe(["tmutil", "latestbackup"])
            if rc == 0 and output.strip():
                return {"status": "warning", "observation": "Time Machine backup exists; restore not verified"}
        return {"status": "unavailable", "observation": "Backup restore verification unavailable"}
    if code == "check_endpoint_protection":
        if sys.platform == "win32":
            rc, output = _probe(["powershell.exe", "-NoProfile", "-NonInteractive",
                "-Command", "(Get-MpComputerStatus).AntivirusEnabled"])
            if rc == 0 and output.strip().lower() in ("true", "false"):
                return {"status": "ok" if output.strip().lower() == "true" else "warning",
                        "observation": "Microsoft Defender antivirus enabled: " + output.strip().lower()}
        return {"status": "unavailable", "observation": "Trusted endpoint protection status unavailable"}
    return None


def report():
    heartbeat = post({"method_type": "device_heartbeat",
        "identifier": os.environ["LIGHTEK_DEVICE_IDENTIFIER"],
        "health_telemetry": collect()})
    for action in heartbeat.get("maintenance_actions", [])[:10]:
        if not isinstance(action, dict):
            continue
        if not isinstance(action.get("id"), int) or isinstance(action.get("id"), bool):
            continue
        if not isinstance(action.get("nonce"), str) or len(action["nonce"]) != 48:
            continue
        try:
            expires_at = datetime.fromisoformat(action["expires_at"].replace("Z", "+00:00"))
            if expires_at <= datetime.now(timezone.utc):
                continue
        except (AttributeError, KeyError, TypeError, ValueError, OverflowError):
            continue
        result = read_only_check(action.get("code"))
        if result is None:
            continue
        post({"method_type": "device_maintenance_report",
            "identifier": os.environ["LIGHTEK_DEVICE_IDENTIFIER"],
            "action_id": action["id"], "nonce": action["nonce"], "result": result})
    return heartbeat


if __name__ == "__main__":
    try:
        report()
    except (KeyError, ValueError, RuntimeError, OSError, urllib.error.URLError) as error:
        print("Lightek device reporting failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
