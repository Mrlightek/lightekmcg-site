#!/usr/bin/env python3
"""Match a CLI list or use upstream's browser profile for its interactive CLI."""
import argparse
import importlib.util
import json
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


def credentials_from_stdin():
    if sys.stdin.isatty():
        return {}
    raw = sys.stdin.buffer.read(8193)
    if not raw:
        return {}
    if len(raw) > 8192:
        raise ValueError("Invalid Studio credential payload")
    credentials = json.loads(raw)
    if not isinstance(credentials, dict):
        raise ValueError("Invalid Studio credential payload")
    return credentials


def renew(driver, page, credentials):
    email, password = (credentials.get(key) for key in ("email", "password"))
    if not all(isinstance(value, str) and value for value in (email, password)):
        raise driver.LoginRequired("The animation service needs the studio operator")
    try:
        driver.auto_login(page, email, password)
    except Exception:
        # Browser exceptions can contain typed values. Do not pass exception details
        # from this phase into worker logs, even when Chromium fails.
        raise driver.LoginRequired("The animation service could not renew its session") from None


def authorized_transfer(driver, page, args, adapters, credentials):
    def send():
        try:
            driver.transfer(page, args, adapters)
        except driver.LoginRequired:
            raise
        except Exception:
            if not page.is_closed() and driver.auth_state(page) == "login":
                raise driver.LoginRequired("Mixamo redirected to Adobe sign-in") from None
            raise
    try:
        send()
    except driver.LoginRequired:
        renew(driver, page, credentials)
        send()


def browser_command(args):
    credentials = credentials_from_stdin()
    driver_path = Path(__file__).resolve().parent / "media_pipeline/character/browser.py"
    spec = importlib.util.spec_from_file_location("lightek_mixamo_browser", driver_path)
    driver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(driver)
    sys.path.insert(0, os.getcwd())

    profile = Path.cwd() / "browser_profile"
    profile.mkdir(mode=0o700, exist_ok=True)
    # Use the browser installation that the worker's interactive CLI uses.
    from playwright.sync_api import sync_playwright

    try:
        with sync_playwright() as runner:
            context = runner.chromium.launch_persistent_context(
                str(profile), headless=True, accept_downloads=True,
                viewport={"width": 1280, "height": 900},
            )
            try:
                page = context.pages[0] if context.pages else context.new_page()
                page.set_default_timeout(15_000)
                if args.command == "renew":
                    renew(driver, page, credentials)
                else:
                    from screens import animations, download, upload

                    transfer = SimpleNamespace(character=args.character, out=args.output, query=args.title.strip(),
                        animation_id=args.animation_id or None, action="transfer", fps=30)
                    authorized_transfer(driver, page, transfer, (animations, download, upload), credentials)
            finally:
                context.close()
    except driver.LoginRequired:
        print("[mixamo] The animation service needs the studio operator.", file=sys.stderr)
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
    commands.add_parser("renew")
    args = parser.parse_args()
    try:
        if args.command == "match":
            match(args.title, args.listing.read_text(encoding="utf-8", errors="replace"))
            return 0
        return browser_command(args)
    except (ValueError, TypeError) as error:
        message = str(error) if args.command == "match" else "The animation service could not read its connection settings."
        print(f"[mixamo] {message}", file=sys.stderr)
        return 1
    except Exception as error:
        print(f"[mixamo] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
