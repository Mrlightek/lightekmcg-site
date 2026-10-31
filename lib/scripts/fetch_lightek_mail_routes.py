#!/usr/bin/env python3
"""Fetch the central application's SMTP recipient allowlist from a mail-only VM."""
import argparse
import json
from pathlib import Path
import sys
import urllib.request
from urllib.parse import urlsplit

from lightek_mail_route_maps import build


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def fetch(config):
    endpoint = urlsplit(config['url'])
    if (endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password
            or endpoint.query or endpoint.fragment or endpoint.path != '/api/lightek-mail/inbound'
            or len(config['token']) < 32):
        raise ValueError('Invalid HTTPS ingress configuration')
    url = config['url'].removesuffix('/inbound') + '/routes'
    request = urllib.request.Request(url, headers={'X-Lightek-Mail-Ingress': config['token']})
    with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
        if response.status != 200:
            raise ValueError('Recipient export unavailable')
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise ValueError('Recipient export too large')
    recipients = json.loads(raw)['recipients']
    if not isinstance(recipients, list) or not all(isinstance(item, str) and not any(char.isspace() for char in item) for item in recipients):
        raise ValueError('Invalid recipient export')
    # Validate the complete export before printing any records or changing maps.
    build('\n'.join(f'{address} lightek' for address in recipients), '')
    return sorted(set(recipients))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='/etc/lightek/mail-ingress.json', type=Path)
    args = parser.parse_args()
    for address in fetch(json.loads(args.config.read_text())):
        print('LIGHTEK_RECIPIENT ' + address)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # urllib exceptions can include sensitive headers; do not emit details.
        print('Central recipient export failed; existing SMTP maps retained', file=sys.stderr)
        sys.exit(1)
