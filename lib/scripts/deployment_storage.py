#!/usr/bin/env python3
"""Bound dependency-build storage and reuse unchanged images; never remove app data."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

SOURCE_LABEL = "io.lightek.source-sha256"
MIB = 1024 * 1024


def docker(*args, check=True):
    return subprocess.run(["docker", *args], text=True, capture_output=True, check=check)


def filesystems(app_root):
    paths = [Path(app_root)]
    result = docker("info", "--format", "{{.DockerRootDir}}", check=False)
    if result.returncode == 0 and result.stdout.strip().startswith("/"):
        paths.append(Path(result.stdout.strip()))
    paths.append(Path("/var/lib/containerd"))
    unique = {}
    for path in paths:
        if path.exists():
            unique.setdefault(path.stat().st_dev, path)
    return list(unique.values())


def shortages(paths, minimum_mib):
    result = []
    for path in paths:
        usage = os.statvfs(path)
        free = usage.f_bavail * usage.f_frsize
        if free < minimum_mib * MIB or usage.f_favail < 4096:
            result.append(f"{path}: {free // MIB} MiB and {usage.f_favail} inodes free")
    return result


def ensure_space(app_root, minimum_mib=2048):
    paths = filesystems(app_root)
    low = shortages(paths, minimum_mib)
    if low:
        print("[storage] Low headroom; reclaiming unused Docker build cache only.", flush=True)
        result = docker("builder", "prune", "--all", "--force", check=False)
        print(result.stdout.strip(), flush=True)
        if result.returncode:
            print(result.stderr.strip(), file=sys.stderr)
        low = shortages(paths, minimum_mib)
    if low:
        raise RuntimeError("Insufficient deployment storage: " + "; ".join(low) +
                           f". Need {minimum_mib} MiB and 4096 free inodes on each affected filesystem. "
                           "Images, containers, volumes, database files, uploads and mail have been retained. "
                           "Review disk allocation or expand storage before retrying.")
    print(f"[storage] At least {minimum_mib} MiB headroom available.", flush=True)


def source_digest(context):
    digest = hashlib.sha256()
    for path in sorted(context.rglob("*")):
        if not path.is_file() or any(part in {".git", "__pycache__"} for part in path.relative_to(context).parts):
            continue
        digest.update(str(path.relative_to(context)).encode() + b"\0")
        digest.update(path.read_bytes() + b"\0")
    return digest.hexdigest()


def legacy_source_is_current(context, image):
    """Adopt an existing version-tagged image only when it postdates clean tracked sources."""
    try:
        dirty = subprocess.run(["git", "-C", str(context), "status", "--porcelain", "--", "."],
                               capture_output=True, text=True, check=True).stdout
        if dirty.strip():
            return False
        changed = subprocess.run(["git", "-C", str(context), "log", "-1", "--format=%ct", "--", "."],
                                 capture_output=True, text=True, check=True).stdout.strip()
        built = datetime.fromisoformat(image["Created"].replace("Z", "+00:00")).astimezone(timezone.utc).timestamp()
        return bool(changed) and built >= int(changed)
    except (subprocess.SubprocessError, ValueError, KeyError, TypeError):
        return False


def ensure_image(image_name, context, app_root, build_mib=4096):
    context = Path(context).resolve()
    fingerprint = source_digest(context)
    result = docker("image", "inspect", image_name, check=False)
    try:
        image = json.loads(result.stdout)[0] if result.returncode == 0 else None
    except (ValueError, IndexError, TypeError):
        image = None
    if image:
        label = (image.get("Config", {}).get("Labels") or {}).get(SOURCE_LABEL)
        if label == fingerprint or (not label and legacy_source_is_current(context, image)):
            print(f"[dependency] Reusing {image_name}; dependency sources unchanged.", flush=True)
            return
    ensure_space(app_root, build_mib)
    subprocess.run(["docker", "build", "--label", f"{SOURCE_LABEL}={fingerprint}",
                    "--tag", image_name, str(context)], check=True)
    # Do not let an image export consume the remaining space needed by the app.
    ensure_space(app_root, 2048)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app-root", required=True)
    parser.add_argument("--minimum-free-mib", type=int, default=2048)
    parser.add_argument("--image")
    parser.add_argument("--context")
    args = parser.parse_args()
    if args.minimum_free_mib < 1:
        parser.error("minimum-free-mib must be positive")
    try:
        if args.image:
            if not args.context:
                parser.error("--context is required with --image")
            ensure_image(args.image, args.context, args.app_root, args.minimum_free_mib)
        else:
            ensure_space(args.app_root, args.minimum_free_mib)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
