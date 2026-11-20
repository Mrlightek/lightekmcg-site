#!/usr/bin/env python3
"""Materialize portable model assets from a .unitypackage without executing Unity."""
import argparse
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import tempfile

MODELS = {".fbx", ".glb", ".gltf"}
PORTABLE = MODELS | {".bin", ".png", ".jpg", ".jpeg", ".webp", ".tga", ".bmp", ".dds", ".ktx2"}
MAX_BYTES = 350 * 1024 * 1024


def portable_path(value):
    parts = value.split("/")
    if (not value.startswith("Assets/") or len(value) > 512 or
            any(part in {"", ".", ".."} for part in parts) or
            any(c == "\\" or c == ":" or ord(c) < 32 for c in value)):
        raise ValueError(f"Invalid Unity asset path {value!r}")
    return PurePosixPath(value)


def unpack(source, output, selection=None):
    with tempfile.TemporaryDirectory(prefix=".unity-", dir=output.parent) as pending:
        entries = {}
        total = 0
        with tarfile.open(source, "r|gz") as archive:
            for index, member in enumerate(archive, 1):
                total += member.size
                if index > 6000 or total > MAX_BYTES:
                    raise ValueError("Unity package exceeds the expanded size or entry limit")
                name = member.name.removeprefix("./")
                if member.isdir():
                    continue
                if not member.isfile():
                    raise ValueError("Unity package contains a link or special entry")
                match = re.fullmatch(r"([a-fA-F0-9]{32})/(pathname|asset)", name)
                if not match:
                    continue
                guid, field = match.groups()
                entry = entries.setdefault(guid, {})
                if field in entry:
                    raise ValueError("Unity package contains duplicate asset data")
                with archive.extractfile(member) as stream:
                    if field == "asset":
                        local = Path(pending) / guid
                        with local.open("wb") as target:
                            shutil.copyfileobj(stream, target, length=1024 * 1024)
                        entry[field] = local
                    else:
                        if member.size > 2048:
                            raise ValueError("Unity asset path is too long")
                        value = stream.read().decode("utf-8").rstrip("\x00\r\n")
                        # Project settings and package sources are outside Assets/.
                        entry[field] = portable_path(value) if value.startswith("Assets/") else None
        portable = {}
        for entry in entries.values():
            path, data = entry.get("pathname"), entry.get("asset")
            if path and data and path.suffix.lower() in PORTABLE:
                if path in portable:
                    raise ValueError(f"Unity package contains multiple copies of {path}")
                portable[path] = data
        models = sorted(str(path) for path in portable if path.suffix.lower() in MODELS)
        if not models:
            raise ValueError("No embedded FBX, GLB or glTF model. Export the prefab or mesh from Unity as FBX and upload it.")
        if selection is None and len(models) != 1:
            listing = ", ".join(models[:5])
            if len(models) > 5:
                listing += f" and {len(models) - 5} more"
            raise ValueError(f"Choose a Unity model path: {listing}")
        selected = selection or models[0]
        if selected not in models:
            raise ValueError(f"Model path {selected!r} is not in the package")
        for path, data in portable.items():
            target = output.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            data.rename(target)
        return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--model-path")
    args = parser.parse_args()
    try:
        print(unpack(args.source, args.output, args.model_path))
    except (OSError, ValueError, tarfile.TarError) as error:
        raise SystemExit(f"Unity package: {error}") from error


if __name__ == "__main__":
    main()
