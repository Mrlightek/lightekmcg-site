#!/usr/bin/env python3
"""Produce the existing isolated-site image context without SSH, DNS or customer secrets."""
import argparse
import base64
import json
import pathlib
import shutil
import subprocess
import tempfile


def installer_helpers(root):
    # Single source for the established installer's private-gem vendoring and
    # delivery adapters. Loading its definitions cannot execute main().
    source = (root / "script/lightek/website_deploy.sh").read_text()
    python = source.split("<<'LIGHTEK_PYTHON'\n", 1)[1].split("\nLIGHTEK_PYTHON", 1)[0]
    namespace = {"__name__": "lightek_fleet_packager"}
    exec(compile(python, "website_deploy.sh", "exec"), namespace)
    return namespace


def build(root, output):
    if output.exists():
        raise ValueError("Build output must be a new directory")
    root = root.resolve()
    # Refuse dirty tracked source so artifact provenance equals its commit label.
    subprocess.run(["git", "diff", "--exit-code", "HEAD"], cwd=root, check=True, stdout=subprocess.DEVNULL)
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    helpers = installer_helpers(root)
    output.mkdir(parents=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix="lightek-fleet-package-") as temporary:
        stage = pathlib.Path(temporary)
        metadata_script = stage / "metadata.rb"
        metadata_script.write_bytes(base64.b64decode(helpers["PAYLOAD"]["metadata.rb"]))
        metadata = stage / "metadata.json"
        subprocess.run(["bundle", "exec", "ruby", str(metadata_script), str(metadata)], cwd=root, check=True)
        meta = json.loads(metadata.read_text())
        if meta["ruby"] != "3.3.6":
            raise ValueError("Fleet image must use the installer's Ruby 3.3.6 runtime")
        for name in ("app", "bin", "config", "db", "lib", "public", "script", "vendor"):
            if (root / name).is_dir():
                helpers["copy_source"](root / name, output / name)
        for name in ("Rakefile", "config.ru", "Gemfile.lock", "package.json", "yarn.lock"):
            if (root / name).is_file():
                shutil.copy2(root / name, output / name)
        for name, encoded in helpers["PAYLOAD"].items():
            if not name.startswith("payload/"):
                continue
            destination = output / name.removeprefix("payload/")
            destination.parent.mkdir(parents=True, exist_ok=True)
            content = base64.b64decode(encoded)
            if destination.exists() and destination.read_bytes() != content:
                raise ValueError("Conflicting installer adapter: " + name)
            destination.write_bytes(content)
        routes = output / "config/routes.rb"
        routes.write_text(helpers["add_routes"](routes.read_text()))
        application = output / "config/application.rb"
        application.write_text(helpers["add_boot_sync_hook"](application.read_text()))
        helpers["make_gemfile"](meta, output)
        dockerfile = base64.b64decode(helpers["PAYLOAD"]["Dockerfile"]).decode()
        (output / "Dockerfile").write_text(dockerfile + '\nLABEL org.opencontainers.image.revision="' + sha + '"\n')
        (output / ".dockerignore").write_text(".env*\ndeployment.env\nconfig/master.key\nconfig/credentials/*.key\n.git\nlog\ntmp\nstorage\n")
        entry = output / "bin/lightek-container-entrypoint"
        entry.write_text('#!/bin/sh\nset -eu\nrm -f /app/tmp/pids/server.pid\nexec "$@"\n')
        for path in (output / "bin").iterdir():
            if path.is_file():
                path.chmod(path.stat().st_mode | 0o111)
        (output / "fleet-build.json").write_text(json.dumps({"source_sha": sha, "bundler": meta["bundler"]}))
        return sha


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    print(build(pathlib.Path.cwd(), args.output))
