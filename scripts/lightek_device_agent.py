#!/usr/bin/env python3
"""Lightek opt-in device reporting and bounded backup sample recovery."""
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
import zlib


RECOVERY_SAMPLE = "lightek-recovery-canary.bin"
MAX_SAMPLE_BYTES = 64 * 1024
MAX_BACKUP_ARCHIVE_BYTES = 16 * 1024 * 1024


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


def _probe(argv, timeout=12, output_limit=400):
    """Execute only fixed, local, read-only OS inspection commands."""
    try:
        completed = subprocess.run(argv, capture_output=True, text=True,
                                   timeout=timeout, check=False, shell=False)
        return completed.returncode, (completed.stdout + completed.stderr)[:output_limit]
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def patch_inventory():
    output_limit = 64 * 1024
    count = None
    source = None
    if sys.platform == "win32":
        rc, output = _probe(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
            "$ErrorActionPreference = 'Stop'; "
            "$searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher(); "
            "$searcher.Online = $false; "
            "$result = $searcher.Search(\"IsInstalled=0 and IsHidden=0 and Type='Software'\"); "
            "if ($result.ResultCode -ne 2) { exit 1 }; $result.Updates.Count"], timeout=60)
        value = output.strip()
        if rc == 0 and value.isascii() and value.isdecimal() and len(value) <= 6:
            count, source = int(value), "Cached Windows Update catalog"
    elif sys.platform == "darwin":
        rc, output = _probe(["/usr/sbin/softwareupdate", "--list"], timeout=90, output_limit=output_limit)
        if rc == 0 and len(output) < output_limit:
            count = sum(line.strip().startswith("* Label:") for line in output.splitlines())
            if count or any(line.strip().rstrip(".") == "No new software available" for line in output.splitlines()):
                source = "Apple Software Update"
    elif sys.platform == "linux" and shutil.which("apt"):
        rc, output = _probe(["apt", "list", "--upgradable"], output_limit=output_limit)
        if rc == 0 and len(output) < output_limit:
            count = sum("[upgradable from:" in line for line in output.splitlines())
            if count or any(line.strip() == "Listing..." for line in output.splitlines()):
                source = "Cached APT catalog"
    if source is None:
        return {"status": "unavailable", "observation": "Trusted patch inventory unavailable"}
    return {"status": "warning" if count else "ok",
            "observation": f"{source} lists {count} available updates; update compliance not verified",
            "available_update_count": count}


def read_only_check(code):
    if code == "refresh_inventory":
        return {"status": "ok", "observation": "Platform: " + platform.system()[:80]}
    if code == "check_patch_status":
        return patch_inventory()
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


def verify_backup_recovery():
    """Recover one configured ZIP member into memory and measure its digest."""
    unavailable = {"status": "unavailable"}
    configured = os.environ.get("LIGHTEK_RECOVERY_ARCHIVE")
    if not configured:
        return unavailable
    try:
        archive = Path(configured)
        if (not archive.is_absolute() or not archive.is_file()
                or archive.stat().st_size > MAX_BACKUP_ARCHIVE_BYTES):
            return unavailable
        with zipfile.ZipFile(archive) as backup:
            entries = [item for item in backup.infolist() if item.filename == RECOVERY_SAMPLE]
            if len(entries) != 1:
                return unavailable
            item = entries[0]
            if (not 0 < item.file_size <= MAX_SAMPLE_BYTES
                    or item.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
                return unavailable
            with backup.open(item) as sample:
                restored = sample.read(MAX_SAMPLE_BYTES + 1)
            if len(restored) != item.file_size:
                return unavailable
            return {"status": "restored", "sha256": hashlib.sha256(restored).hexdigest()}
    except (EOFError, OSError, RuntimeError, ValueError, zipfile.BadZipFile, zlib.error):
        return unavailable


def report():
    identifier = os.environ["LIGHTEK_DEVICE_IDENTIFIER"]
    heartbeat = post({"method_type": "device_heartbeat",
        "identifier": identifier,
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
        credentials = {"identifier": identifier, "action_id": action["id"], "nonce": action["nonce"]}
        if action.get("code") == "verify_backup_recovery":
            try:
                claim = post({"method_type": "device_maintenance_claim", **credentials})
            except urllib.error.HTTPError as error:
                if error.code in (403, 404, 422):
                    continue
                raise
            if claim.get("action_id") != action["id"] or expires_at <= datetime.now(timezone.utc):
                continue
            result = verify_backup_recovery()
        else:
            result = read_only_check(action.get("code"))
        if result is None:
            continue
        post({"method_type": "device_maintenance_report", **credentials, "result": result})
    return heartbeat


if __name__ == "__main__":
    try:
        report()
    except (KeyError, ValueError, RuntimeError, OSError, urllib.error.URLError) as error:
        print("Lightek device reporting failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
