"""POSIX atomic cutover for one explicitly armed, quiesced endpoint directory."""
import argparse
import ctypes
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
import time

from lightek_backup_restore import MAX_EXPANDED, MAX_FILES, copy_hash, stage_backup_restore

REFERENCE = re.compile(r"lightek-restore-[0-9a-f]{32}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")


def exchange(first, second):
    libc = ctypes.CDLL(None, use_errno=True)
    paths = (os.fsencode(first), os.fsencode(second))
    if sys.platform == "linux":
        operation = getattr(libc, "renameat2", None)
        if operation is None:
            raise OSError(errno.ENOSYS, "Atomic exchange unavailable")
        operation.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        result = operation(-100, paths[0], -100, paths[1], 2)
    elif sys.platform == "darwin":
        operation = libc.renamex_np
        operation.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        result = operation(*paths, 2)
    else:
        raise OSError(errno.ENOSYS, "Atomic exchange unavailable")
    if result != 0:
        raise OSError(ctypes.get_errno(), "Atomic exchange failed")


def private_policy(digest, operation, reference=None):
    configured = Path(os.environ.get("LIGHTEK_RECOVERY_CUTOVER_AUTHORIZATION", ""))
    staging = Path(os.environ.get("LIGHTEK_RECOVERY_STAGING", ""))
    if (not configured.is_absolute() or not staging.is_absolute()
            or configured.resolve(strict=True) != configured or staging.resolve(strict=True) != staging):
        raise ValueError("A local authorization and a private staging directory are required")
    item = configured.lstat()
    if not stat.S_ISREG(item.st_mode) or item.st_uid != os.geteuid() or item.st_mode & 0o077 or item.st_size > 4096:
        raise ValueError("Untrusted local authorization")
    policy = json.loads(configured.read_text(encoding="utf-8"))
    if not isinstance(policy, dict):
        raise ValueError("Invalid authorization")
    deadline = policy.get("expires_at")
    if (policy.get("operation") != operation or policy.get("sha256") != digest
            or policy.get("reference") != reference or type(deadline) is not int
            or not time.time() < deadline <= time.time() + 1800):
        raise ValueError("A fresh local authorization for the exact operation is required")
    live = Path(policy["live_directory"])
    if (not live.is_absolute() or live.resolve(strict=True) != live or len(live.parts) < 3
            or live == staging or live in staging.parents or staging in live.parents):
        raise ValueError("Unsafe live directory")
    live_stat, staging_stat = live.lstat(), staging.lstat()
    if (not stat.S_ISDIR(live_stat.st_mode) or not stat.S_ISDIR(staging_stat.st_mode)
            or live_stat.st_dev != staging_stat.st_dev or live_stat.st_uid != os.geteuid()
            or staging_stat.st_uid != os.geteuid() or staging_stat.st_mode & 0o077
            or live_stat.st_mode & 0o7000 or live.is_mount()):
        raise ValueError("Directories must be local, owned by the agent, and on the same mount")
    return live, staging


def inode(path):
    current = path.lstat()
    if not stat.S_ISDIR(current.st_mode):
        raise ValueError("Expected a directory")
    return current.st_ino


def sync_directory(path):
    fd = os.open(path, os.O_DIRECTORY | os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def tree_manifest(root, durable=False):
    manifest = {}
    remaining = MAX_EXPANDED
    for directory, dirs, filenames in os.walk(root, followlinks=False):
        parent = Path(directory)
        for name in dirs:
            if not stat.S_ISDIR((parent / name).lstat().st_mode):
                raise ValueError("Links cannot enter the live restore")
            if durable:
                (parent / name).chmod(0o700)
            manifest[(parent / name).relative_to(root).as_posix()] = None
        for name in filenames:
            file = parent / name
            if not stat.S_ISREG(file.lstat().st_mode) or len(manifest) >= MAX_FILES:
                raise ValueError("Unexpected restored file")
            if durable:
                file.chmod(0o600)
            with file.open("rb") as data:
                size, digest = copy_hash(data, None, remaining)
                if durable:
                    os.fsync(data.fileno())
            remaining -= size
            manifest[file.relative_to(root).as_posix()] = digest
        if durable:
            sync_directory(parent)
        if len(manifest) > MAX_FILES:
            raise ValueError("Restored path count exceeded")
    return hashlib.sha256(json.dumps(manifest, sort_keys=True).encode("utf-8")).hexdigest()


def restore_lock(staging):
    import fcntl
    fd = os.open(staging / ".cutover.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    lock = os.fdopen(fd, "a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        lock.close()
        raise
    return lock


def consume_authorization():
    authorization = Path(os.environ["LIGHTEK_RECOVERY_CUTOVER_AUTHORIZATION"])
    authorization.unlink()
    sync_directory(authorization.parent)


def cutover_backup_restore(digest):
    if sys.platform not in ("linux", "darwin") or not isinstance(digest, str) or not DIGEST.fullmatch(digest):
        return {"status": "unavailable"}
    try:
        live, staging = private_policy(digest, "cutover")
        with restore_lock(staging):
            live, staging = private_policy(digest, "cutover")
            staged = stage_backup_restore(digest)
            if staged["status"] != "staged":
                return staged
            reference = staged["staging_reference"]
            rollback = staging / reference
            original = live.stat()
            restored = rollback.stat()
            if restored.st_gid != original.st_gid:
                return {"status": "unavailable"}
            rollback.chmod(stat.S_IMODE(original.st_mode))
            manifest = tree_manifest(rollback, durable=True)
            journal = staging / (reference + ".json")
            with journal.open("x", encoding="utf-8") as file:
                json.dump({"live": str(live), "original_inode": original.st_ino, "restored_inode": restored.st_ino,
                           "sha256": digest, "manifest": manifest}, file)
                file.flush()
                os.fsync(file.fileno())
            sync_directory(staging)
            sync_directory(live.parent)
            # Recheck the local authorization after staging and immediately before activation.
            if private_policy(digest, "cutover") != (live, staging) or inode(live) != original.st_ino:
                return {"status": "unavailable"}
            consume_authorization()
            exchange(live, rollback)
            try:
                if inode(rollback) != original.st_ino or inode(live) != restored.st_ino or tree_manifest(live) != manifest:
                    raise ValueError("Restored tree verification failed")
                sync_directory(staging)
                sync_directory(live.parent)
            except (OSError, ValueError):
                if inode(live) == restored.st_ino and inode(rollback) == original.st_ino:
                    exchange(live, rollback)
                    sync_directory(staging)
                    sync_directory(live.parent)
                    return {"status": "rolled_back"}
                return {"status": "failed"}
            return {"status": "activated", "sha256": digest, "rollback_reference": reference}
    except (OSError, AttributeError, KeyError, TypeError, ValueError):
        return {"status": "failed"}


def rollback_cutover(digest, reference):
    if not DIGEST.fullmatch(digest) or not REFERENCE.fullmatch(reference):
        raise ValueError("Invalid rollback reference")
    live, staging = private_policy(digest, "rollback", reference)
    with restore_lock(staging):
        live, staging = private_policy(digest, "rollback", reference)
        rollback = staging / reference
        journal = staging / (reference + ".json")
        journal_stat = journal.lstat()
        if not stat.S_ISREG(journal_stat.st_mode) or journal_stat.st_uid != os.geteuid() or journal_stat.st_size > 4096:
            raise ValueError("Untrusted rollback journal")
        record = json.loads(journal.read_text(encoding="utf-8"))
        if (record["live"] != str(live) or record["sha256"] != digest
                or inode(live) != record["restored_inode"] or inode(rollback) != record["original_inode"]):
            raise ValueError("Live and retained directories do not match the recorded cutover")
        consume_authorization()
        exchange(live, rollback)
        sync_directory(staging)
        sync_directory(live.parent)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Restore the retained pre-cutover directory after separately arming rollback.")
    parser.add_argument("digest")
    parser.add_argument("reference")
    inputs = parser.parse_args()
    rollback_cutover(inputs.digest, inputs.reference)
