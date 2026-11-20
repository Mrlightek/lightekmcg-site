#!/usr/bin/env python3
"""Match a CLI list or use upstream's browser profile for its interactive CLI."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import sys
from types import SimpleNamespace


def match(title, listing):
    rows = re.findall(r"^\s*\[[ *]\]\s+(\d{1,20})\s+(.+?)\s*$", listing, re.MULTILINE)
    matches = {key for key, name in rows if name.casefold() == title.strip().casefold()}
    if len(matches) != 1:
        choices = ", ".join(f"{name} ({key})" for key, name in rows[:12])
        raise ValueError(f"Expected one match for {title!r}; enter an animation ID. Results: {choices or 'none'}")
    print(matches.pop())


def transfer(character, output, title, animation_id):
    driver_path = Path(__file__).resolve().parent / "media_pipeline/character/browser.py"
    spec = importlib.util.spec_from_file_location("lightek_mixamo_browser", driver_path)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    sys.path.insert(0, os.getcwd())
    from screens import animations, download, upload

    driver.PROFILE = Path.cwd() / "browser_profile"
    driver.PROFILE.mkdir(mode=0o700, exist_ok=True)
    args = SimpleNamespace(character=character, out=output, query=title.strip(),
                           animation_id=animation_id or None, action="transfer", fps=30)
    # Use the browser installation that the worker's interactive CLI uses.
    from playwright.sync_api import sync_playwright

    try:
        with sync_playwright() as runner:
            context = runner.chromium.launch_persistent_context(
                str(driver.PROFILE), headless=True, accept_downloads=True,
                viewport={"width": 1280, "height": 900},
            )
            try:
                page = context.pages[0] if context.pages else context.new_page()
                page.set_default_timeout(15_000)
                try:
                    driver.transfer(page, args, (animations, download, upload))
                except driver.LoginRequired:
                    raise
                except Exception:
                    if not page.is_closed() and driver.auth_state(page) == "login":
                        raise driver.LoginRequired("Mixamo redirected to Adobe sign-in")
                    raise
            finally:
                context.close()
    except driver.LoginRequired as error:
        print(f"[mixamo] {error}", file=sys.stderr)
        return 42
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    search = commands.add_parser("match")
    search.add_argument("title")
    search.add_argument("listing", type=Path)
    process = commands.add_parser("transfer")
    process.add_argument("character", type=Path)
    process.add_argument("output", type=Path)
    process.add_argument("title")
    process.add_argument("animation_id")
    args = parser.parse_args()
    try:
        if args.command == "match":
            match(args.title, args.listing.read_text(encoding="utf-8", errors="replace"))
            return 0
        return transfer(args.character, args.output, args.title, args.animation_id)
    except Exception as error:
        print(f"[mixamo] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
