#!/usr/bin/env python3
"""Build exact SMTP recipient routes; never generate a catch-all transport."""
import argparse
from pathlib import Path
import re

DOMAIN = r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}'
ADDRESS = re.compile(r'[a-z0-9][a-z0-9._+\-]{0,63}@' + DOMAIN)


def build(recipients, domains):
    addresses = set()
    names = set()
    for line in recipients.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        fields = line.split()
        if len(fields) != 2 or not ADDRESS.fullmatch(fields[0]) or fields[1] != 'lightek':
            raise ValueError('Invalid recipient map; existing routes retained')
        addresses.add(fields[0])
        names.add(fields[0].split('@')[1])
    if not addresses:
        raise ValueError('Empty recipient map; existing routes retained')
    # Preserve domains used by existing Dovecot mailboxes as well as Rails accounts.
    for line in domains.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        fields = line.split()
        if len(fields) != 2 or not re.fullmatch(DOMAIN, fields[0]):
            raise ValueError('Invalid virtual domain map; existing routes retained')
        names.add(fields[0])
    return ('\n'.join(f'{name} OK' for name in sorted(names)) + '\n',
            '\n'.join(f'{address} lightek_mail:' for address in sorted(addresses)) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipients', type=Path, required=True)
    parser.add_argument('--domains', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    domains, routes = build(args.recipients.read_text(), args.domains.read_text())
    (args.output / 'lightek_domains').write_text(domains)
    (args.output / 'lightek_transports').write_text(routes)


if __name__ == '__main__':
    main()
