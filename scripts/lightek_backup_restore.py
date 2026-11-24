"""Restore a verified ZIP snapshot to a fresh local staging directory."""
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import stat
import tempfile
import uuid
import zipfile
import zlib

MAX_ARCHIVE = 256 * 1024 * 1024
MAX_EXPANDED = 512 * 1024 * 1024
MAX_FILES = 1024
CHUNK = 1024 * 1024
SAFE_PART = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}\Z")
RESERVED = re.compile(r"(?:con|prn|aux|nul|com[1-9]|lpt[1-9])\Z", re.I)


def member_parts(name):
    parts = name.rstrip("/").split("/")
    if (len(parts) > 12 or not all(SAFE_PART.fullmatch(part) and not part.endswith(".")
            and not RESERVED.fullmatch(part.split(".", 1)[0]) for part in parts)):
        raise ValueError("Unsupported backup member name")
    return parts


def copy_hash(source, output, cap):
    digest = hashlib.sha256()
    size = 0
    while chunk := source.read(CHUNK):
        size += len(chunk)
        if size > cap:
            raise ValueError("Backup exceeds size limit")
        digest.update(chunk)
        if output is not None:
            output.write(chunk)
    return size, digest.hexdigest()


def restore_files(archive, staged):
    total = 0
    count = 0
    entries = archive.infolist()
    if len(entries) > MAX_FILES:
        raise ValueError("Backup contains too many entries")
    seen = set()
    parent_spellings = {}
    for entry in entries:
        parents = member_parts(entry.filename)
        canonical = tuple(part.lower() for part in parents)
        if canonical in seen:
            raise ValueError("Duplicate destination")
        seen.add(canonical)
        for size in range(1, len(parents) + 1):
            prefix = canonical[:size]
            original = tuple(parents[:size])
            if parent_spellings.setdefault(prefix, original) != original:
                raise ValueError("Destination names disagree in case")
        kind = stat.S_IFMT(entry.external_attr >> 16)
        if entry.is_dir():
            if kind not in (0, stat.S_IFDIR):
                raise ValueError("Unsupported directory entry")
            continue
        if (kind not in (0, stat.S_IFREG) or entry.file_size > MAX_EXPANDED - total
                or entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED)):
            raise ValueError("Unsupported backup member")
        target = staged.joinpath(*PurePosixPath(*parents).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as source, target.open("xb") as output:
            size, digest = copy_hash(source, output, entry.file_size)
        with target.open("rb") as written:
            if size != entry.file_size or copy_hash(written, None, size) != (size, digest):
                raise ValueError("Restored content could not be read back")
        count += 1
        total += size
    if not count:
        raise ValueError("Backup contains no files")
    return count, total


def stage_backup_restore(expected_digest):
    if not isinstance(expected_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
        return {"status": "unavailable"}
    archive = Path(os.environ.get("LIGHTEK_RECOVERY_ARCHIVE", ""))
    recovery_root = Path(os.environ.get("LIGHTEK_RECOVERY_STAGING", ""))
    try:
        if (not archive.is_absolute() or not archive.is_file()
                or not recovery_root.is_absolute() or not recovery_root.is_dir()):
            return {"status": "unavailable"}
        with tempfile.TemporaryDirectory(prefix=".lightek-restore-", dir=recovery_root) as directory:
            workspace = Path(directory)
            local_archive = workspace / "source.zip"
            with archive.open("rb") as source, local_archive.open("xb") as output:
                _, digest = copy_hash(source, output, MAX_ARCHIVE)
            if digest != expected_digest:
                return {"status": "mismatch"}
            staged = workspace / "files"
            staged.mkdir(mode=0o700)
            with zipfile.ZipFile(local_archive) as backup:
                count, size = restore_files(backup, staged)
            reference = "lightek-restore-" + uuid.uuid4().hex
            staged.rename(recovery_root / reference)
            return {"status": "staged", "sha256": digest, "staging_reference": reference,
                    "file_count": count, "byte_count": size}
    except (EOFError, OSError, RuntimeError, ValueError, zipfile.BadZipFile, zlib.error):
        return {"status": "failed"}
