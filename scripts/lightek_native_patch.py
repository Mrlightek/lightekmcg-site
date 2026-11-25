"""Unprivileged client for the fixed Windows and macOS update brokers."""
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

WINDOWS_TARGET = re.compile(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}=[1-9][0-9]{0,8}\Z")
MACOS_TARGET = re.compile(r"[A-Za-z0-9][A-Za-z0-9 ()_.+-]{0,119}\|[A-Za-z0-9][A-Za-z0-9.-]{0,79}\|[A-Za-z0-9][A-Za-z0-9.-]{0,49}\Z")
MACOS_BROKER = "/usr/local/libexec/lightek-macos-patch"
WINDOWS_TASK = r"\LightekEndpointPatch"


def checked_result(result, target):
    if result in ({"status": "unavailable"}, {"status": "failed"}, {"status": "pending_restart"}):
        return result
    if result == {"status": "installed", "target": target}:
        return result
    return {"status": "failed"}


def deploy_macos_patch(target):
    if not isinstance(target, str) or not MACOS_TARGET.fullmatch(target) or not Path(MACOS_BROKER).is_file():
        return {"status": "unavailable"}
    try:
        reply = subprocess.run(["/usr/bin/sudo", "-n", MACOS_BROKER], input=target + "\n",
                               capture_output=True, text=True, check=True)
        return checked_result(json.loads(reply.stdout), target)
    except (OSError, subprocess.SubprocessError, ValueError):
        return {"status": "failed"}


def deploy_windows_patch(target, expires_at):
    if not isinstance(target, str) or not WINDOWS_TARGET.fullmatch(target):
        return {"status": "unavailable"}
    program_data = os.environ.get("ProgramData")
    system_root = os.environ.get("SystemRoot")
    if not program_data or not system_root:
        return {"status": "unavailable"}
    root = Path(program_data) / "Lightek" / "EndpointPatch"
    inbox = root / "inbox"
    outbox = root / "outbox"
    if not inbox.is_dir() or not outbox.is_dir():
        return {"status": "unavailable"}

    request_id = uuid.uuid4().hex
    temporary = inbox / (request_id + ".tmp")
    try:
        with temporary.open("x", encoding="ascii") as queue:
            json.dump({"id": request_id, "target": target, "deadline": expires_at.isoformat()}, queue)
        temporary.rename(inbox / "request.json")
        executable = Path(system_root) / "System32" / "schtasks.exe"
        subprocess.run([str(executable), "/Run", "/TN", WINDOWS_TASK],
                       capture_output=True, text=True, check=True, timeout=30)
        deadline = time.monotonic() + 90 * 60
        while time.monotonic() < deadline:
            try:
                with (outbox / "result.json").open(encoding="utf-8") as result_file:
                    receipt = json.loads(result_file.read(1024))
                if isinstance(receipt, dict) and receipt.get("id") == request_id:
                    return checked_result(receipt.get("result"), target)
            except (FileNotFoundError, PermissionError, ValueError):
                pass
            time.sleep(5)
    except (OSError, subprocess.SubprocessError):
        return {"status": "unavailable"}
    finally:
        temporary.unlink(missing_ok=True)
    return {"status": "failed"}
