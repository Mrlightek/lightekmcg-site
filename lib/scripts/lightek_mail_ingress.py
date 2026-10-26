#!/usr/bin/env python3
"""Postfix pipe: forward one envelope recipient and raw MIME over verified HTTPS."""
import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipient", required=True)
    parser.add_argument("--config", default="/etc/lightek/mail-ingress.json")
    args = parser.parse_args()
    if not re.fullmatch(r"[^\s<>@,;]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,63}", args.recipient):
        return 65
    with open(args.config, encoding="utf-8") as file:
        config = json.load(file)
    endpoint = urlsplit(config["url"])
    if endpoint.scheme != "https" or endpoint.username or endpoint.password:
        return 78
    raw = sys.stdin.buffer.read(10 * 1024 * 1024 + 1)
    if len(raw) > 10 * 1024 * 1024:
        return 65
    request = urllib.request.Request(config["url"], data=raw, method="POST", headers={
        "Content-Type": "message/rfc822",
        "X-Lightek-Mail-Ingress": config["token"],
        "X-Lightek-Mail-Recipients": json.dumps([args.recipient.lower()]),
    })
    # No redirects: never forward the ingress credential to a redirected host.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *unused):
            return None
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=30) as response:
            return 0 if response.status == 202 else 75
    except (urllib.error.URLError, TimeoutError, OSError):
        # Keep mail in Postfix's queue on application/auth/config/network failures.
        print("Lightek mail ingress temporarily unavailable; retaining queued message", file=sys.stderr)
        return 75


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        print("Lightek mail ingress configuration unavailable", file=sys.stderr)
        sys.exit(75)
