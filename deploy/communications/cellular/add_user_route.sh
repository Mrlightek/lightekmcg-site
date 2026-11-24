#!/bin/sh
set -eu
exec /usr/bin/python3 -I /usr/local/libexec/lightek_cellular_routes.py "$@"
