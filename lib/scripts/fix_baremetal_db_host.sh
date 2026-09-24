#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/root/apps/lightekmcg-site}"
BUILDER="${REPO_ROOT}/lib/scripts/build_baremetal_env.sh"
TARGET_ENV="${TARGET_ENV:-/etc/lightek/lightekmcg-site.env}"

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -f "${TARGET_ENV}" ]] || { echo "ERROR: missing ${TARGET_ENV}"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
cp "${TARGET_ENV}" "${TARGET_ENV}.${STAMP}.bak"

# Fix the CURRENT bare-metal env immediately.
if grep -q '^DB_HOST=' "${TARGET_ENV}"; then
  sed -i 's/^DB_HOST=.*/DB_HOST="127.0.0.1"/' "${TARGET_ENV}"
else
  printf '\nDB_HOST="127.0.0.1"\n' >> "${TARGET_ENV}"
fi

# Keep the existing POSTGRES_HOST as harmless compatibility metadata if present.
if grep -q '^POSTGRES_HOST=' "${TARGET_ENV}"; then
  sed -i 's/^POSTGRES_HOST=.*/POSTGRES_HOST="127.0.0.1"/' "${TARGET_ENV}"
fi

# Patch the generator so future runs/servers produce DB_HOST too.
if [[ -f "${BUILDER}" ]]; then
  cp "${BUILDER}" "${BUILDER}.${STAMP}.bak"

  python3 - "${BUILDER}" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

# Force DB_HOST alongside POSTGRES_HOST.
needle = 'VALUES[POSTGRES_HOST]="127.0.0.1"\n'
replacement = 'VALUES[DB_HOST]="127.0.0.1"\nVALUES[POSTGRES_HOST]="127.0.0.1"\n'
if needle in src and 'VALUES[DB_HOST]="127.0.0.1"' not in src:
    src = src.replace(needle, replacement)

# Ensure DB_HOST is emitted to the target env.
keys_needle = '  POSTGRES_HOST\n'
if keys_needle in src and '  DB_HOST\n' not in src:
    src = src.replace(keys_needle, '  DB_HOST\n' + keys_needle)

path.write_text(src)
print(f"Patched {path}")
PY

  bash -n "${BUILDER}"
fi

echo
echo "=== CURRENT DB HOST VALUES ==="
grep -E '^(DB_HOST|POSTGRES_HOST|POSTGRES_DB|POSTGRES_USER)=' "${TARGET_ENV}" | sed -E 's/(POSTGRES_USER=).*/\1[PRESENT]/'

echo
echo "Done."
echo "Rails database.yml reads DB_HOST, so bare-metal Rails will now use 127.0.0.1."
