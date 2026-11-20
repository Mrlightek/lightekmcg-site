#!/usr/bin/env python3
"""Headless Mixamo CLI using the pinned mixamo-mcp screen adapters."""
import argparse
from contextlib import contextmanager
import fcntl
import os
from pathlib import Path
import re
import sys
import tempfile
import time
from urllib.parse import urlencode, urlsplit

HOME = Path(os.environ.get("LIGHTEK_CHARACTER_HOME",
                           Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "lightek-character"))
PROFILE = Path(os.environ.get("MIXAMO_PROFILE", HOME / "profile")).expanduser().resolve()
ADAPTER = HOME / "mixamo-mcp-8bdb0a3ed91fdc1fadc469701e09ecb0bdb7aefd"
SITE = "https://www.mixamo.com"
ADOBE_HOSTS = {"auth.services.adobe.com", "ims-na1.adobelogin.com", "adobelogin.com",
               "account.adobe.com", "adobeid-na1.services.adobe.com"}
MIXAMO_HOSTS = {"www.mixamo.com", "mixamo.com"}
SIGNIN = re.compile(r"^\s*(log\s*in|sign\s*in)\s*$", re.I)


class LoginRequired(RuntimeError):
    pass


class RigReviewRequired(RuntimeError):
    pass


def host(page):
    url = urlsplit(page.url)
    return url.hostname if url.scheme == "https" else None


def visible(locator):
    for item in locator.all():
        if item.is_visible():
            return item
    return None


def sign_in_button(page):
    return visible(page.get_by_role("button", name=SIGNIN)) or visible(page.get_by_role("link", name=SIGNIN))


def auth_state(page):
    current = host(page)
    if current in ADOBE_HOSTS:
        return "login"
    if current not in MIXAMO_HOSTS:
        return "unknown"
    if sign_in_button(page):
        return "login"
    if visible(page.locator('button:has-text("Upload Character")')):
        return "ready"
    return "unknown"


def wait_state(page, wait=25):
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        try:
            state = auth_state(page)
            if state != "unknown":
                return state
        except Exception as error:
            # A page can replace its document during an Adobe redirect.
            if "Execution context was destroyed" not in str(error):
                raise
        time.sleep(0.25)
    return "unknown"


def open_index(page):
    response = page.goto(SITE, wait_until="domcontentloaded", timeout=30_000)
    if response and response.status >= 400:
        raise RuntimeError(f"Mixamo returned HTTP {response.status}")


def check(page):
    open_index(page)
    state = wait_state(page)
    if state == "login":
        raise LoginRequired("Saved Mixamo session requires sign-in")
    if state != "ready":
        raise RuntimeError("Mixamo loaded without a recognizable authenticated or sign-in screen")


def challenge(page):
    return visible(page.locator(
        'input[autocomplete="one-time-code"], input[name*="otp" i], input[name*="verificationCode" i], '
        'iframe[title*="captcha" i]'
    )) or visible(page.get_by_text(
        re.compile(r"verification code|verify your identity|check your email|two.step verification", re.I)
    ))


def submit_form(page, field):
    button = visible(page.get_by_role("button", name=re.compile(r"^\s*(continue|sign in|log in|next)\s*$", re.I)))
    if button:
        button.click()
    else:
        field.press("Enter")


def auto_login(page, email=None, password=None):
    open_index(page)
    state = wait_state(page)
    if state == "ready":
        return
    if state != "login":
        raise RuntimeError("Could not identify the Mixamo sign-in screen")
    if host(page) in MIXAMO_HOSTS:
        button = sign_in_button(page)
        if button:
            button.click()

    submitted_email = submitted_password = False
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        state = auth_state(page)
        if state == "ready":
            return
        if host(page) in ADOBE_HOSTS:
            if challenge(page):
                raise LoginRequired("Adobe requested interactive verification")
            password_input = visible(page.locator('input[type="password"]'))
            email_input = visible(page.locator('input[type="email"], input[autocomplete="username"], input[name="username"]'))
            if password_input and not submitted_password:
                if not password:
                    raise LoginRequired("Adobe requested a password")
                password_input.fill(password)
                submit_form(page, password_input)
                submitted_password = True
            elif email_input and not submitted_email:
                if not email:
                    raise LoginRequired("Adobe requested an email address")
                email_input.fill(email)
                submit_form(page, email_input)
                submitted_email = True
        time.sleep(0.35)
    if auth_state(page) == "login":
        raise LoginRequired("Non-interactive Adobe sign-in could not finish")
    raise RuntimeError("Mixamo did not return a recognizable page after sign-in")


def manual_login(page):
    open_index(page)
    if wait_state(page, 10) == "ready":
        return
    print("Complete Adobe sign-in and verification in the Chromium window.", file=sys.stderr, flush=True)
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        if wait_state(page, 1) == "ready":
            return
        time.sleep(0.4)
    raise LoginRequired("Mixamo session still requires sign-in after ten minutes")


def confirm_rig(page, upload, allow_manual):
    deadline = time.monotonic() + (900 if allow_manual else 300)
    had_modal = False
    clicked = set()
    marker_prompted = False
    while time.monotonic() < deadline:
        if auth_state(page) == "login":
            raise LoginRequired("Mixamo session expired during rigging")
        modal = page.locator(".autorig-modal")
        if modal.count() and modal.first.is_visible():
            had_modal = True
            status = upload.get_status(page.content())
            state = status.get("state")
            if state == "markers":
                if not allow_manual:
                    raise RigReviewRequired("Mixamo needs manual rig marker placement")
                if not marker_prompted:
                    print("Place the Mixamo rig markers and click Next. The script will finish the download.", file=sys.stderr)
                    marker_prompted = True
            if state == "error":
                raise RuntimeError(status.get("text", "Mixamo rejected the skeleton"))
            if state in {"review", "change_character"} and state not in clicked:
                upload.confirm_review(page)
                clicked.add(state)
        elif had_modal and auth_state(page) == "ready":
            return
        time.sleep(0.5)
    raise RuntimeError("Mixamo rigging did not complete within five minutes")


def select_motion(page, animations, query, animation_id):
    route = urlencode({"page": 1, "type": "Motion,MotionPack", "query": query})
    page.goto(f"{SITE}/#/?{route}", wait_until="domcontentloaded", timeout=30_000)
    page.locator(".product-animation .product-image img").first.wait_for(timeout=25_000)
    items = animations.get_animation_list(page.content())["items"]
    if animation_id:
        matches = [item for item in items if item["id"] == animation_id]
    else:
        matches = [item for item in items if item["id"] and item["name"].strip().casefold() == query.casefold()]
    if len(matches) != 1:
        options = ", ".join(f"{item['name']} ({item['id']})" for item in items[:10] if item["id"])
        raise RuntimeError(f"Expected exactly one animation match. Results: {options or 'none'}")
    selected = matches[0]["id"]
    animations.select_animation(page, selected)
    page.locator('.product-animation.product-selected').filter(
        has=page.locator(f'img[src*="/motions/{selected}/"]')
    ).first.wait_for(timeout=25_000)
    page.locator(".animation-settings").first.wait_for(timeout=25_000)


def transfer(page, args, adapters):
    animations, download, upload = adapters
    if not args.character.is_file() or args.character.suffix.lower() != ".fbx":
        raise ValueError("--character must be a local FBX")
    check(page)
    upload.upload_file(page, str(args.character.resolve()))
    confirm_rig(page, upload, allow_manual=args.action == "rig")
    select_motion(page, animations, args.query, args.animation_id)
    if auth_state(page) == "login":
        raise LoginRequired("Mixamo session expired before download")
    download.open_modal(page)
    selects = page.locator(".asset-download-modal select")
    selects.nth(0).select_option(download.FORMAT_OPTIONS["fbx"])
    selects.nth(1).select_option("true")
    selects.nth(2).select_option(str(args.fps))
    output = args.out.absolute()
    if output.suffix.lower() != ".fbx":
        raise ValueError("--out must end in .fbx")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".mixamo-", dir=output.parent) as staging:
        pending = Path(staging) / "motion.fbx"
        download.confirm(page, str(pending))
        with pending.open("rb") as handle:
            if not handle.read(23).startswith(b"Kaydara FBX Binary"):
                raise RuntimeError("Mixamo did not return a binary FBX")
        os.replace(pending, output)


@contextmanager
def open_browser(headless):
    from playwright.sync_api import sync_playwright

    PROFILE.mkdir(mode=0o700, parents=True, exist_ok=True)
    if PROFILE.stat().st_uid != os.getuid() or PROFILE.stat().st_mode & 0o077:
        raise RuntimeError("Mixamo profile must be owned by this user with mode 0700")
    os.environ.setdefault("PLAYWRIGHT_BROWSERS_PATH", str(HOME / "browsers"))
    with (PROFILE / ".lightek.lock").open("a", encoding="utf-8") as lock:
        deadline = time.monotonic() + 30
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise RuntimeError("Mixamo profile is busy")
                time.sleep(0.25)
        with sync_playwright() as runner:
            context = runner.chromium.launch_persistent_context(
                str(PROFILE), headless=headless, accept_downloads=True,
                viewport={"width": 1280, "height": 900},
            )
            try:
                page = context.pages[0] if context.pages else context.new_page()
                page.set_default_timeout(15_000)
                yield page
            finally:
                context.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    for name in ("check", "auto-login", "login"):
        actions.add_parser(name)
    for name in ("transfer", "rig"):
        process = actions.add_parser(name)
        process.add_argument("--character", type=Path, required=True)
        process.add_argument("--out", type=Path, required=True)
        process.add_argument("--query", required=True)
        process.add_argument("--animation-id")
        process.add_argument("--fps", type=int, choices=[24, 30, 60], default=30)
    args = parser.parse_args()
    if args.action in {"transfer", "rig"} and args.animation_id and not re.fullmatch(r"[0-9]+", args.animation_id):
        parser.error("--animation-id must be numeric")

    os.umask(0o077)
    try:
        with open_browser(args.action not in {"login", "rig"}) as page:
            try:
                if args.action == "check":
                    check(page)
                elif args.action == "auto-login":
                    auto_login(page, os.environ.get("MIXAMO_EMAIL"), os.environ.get("MIXAMO_PASSWORD"))
                elif args.action == "login":
                    manual_login(page)
                else:
                    sys.path.insert(0, str(ADAPTER))
                    from screens import animations, download, upload
                    transfer(page, args, (animations, download, upload))
            except (LoginRequired, RigReviewRequired):
                raise
            except Exception:
                if not page.is_closed() and auth_state(page) == "login":
                    raise LoginRequired("Mixamo redirected to Adobe sign-in")
                raise
    except LoginRequired as error:
        print(f"Mixamo authentication: {error}", file=sys.stderr)
        return 42
    except RigReviewRequired as error:
        print(f"Mixamo rigging: {error}", file=sys.stderr)
        return 3
    except Exception as error:
        # Browser errors from form actions can include details about what was
        # typed. Keep credential-bearing attempts out of logs.
        detail = "Error during non-interactive sign-in" if args.action == "auto-login" else str(error)
        print(f"Mixamo browser: {detail}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
