#!/bin/bash
set -e

# Clear a stale server pid left behind if a container was killed
rm -f /app/tmp/pids/server.pid

# Wait for Postgres before the app tries to connect
until pg_isready -h "${DB_HOST:-db}" -p 5432 -U "${POSTGRES_USER:-postgres}" >/dev/null 2>&1; do
  echo "Waiting for Postgres at ${DB_HOST:-db}..."
  sleep 1
done

exec "$@"
