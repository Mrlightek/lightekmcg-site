#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="script/store_gmail_api_vault_credentials.rb"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/remove_gmail_sender_from_vault_${STAMP}"

mkdir -p "$BACKUP/$(dirname "$FILE")"
cp "$FILE" "$BACKUP/$FILE"

python3 <<'PY'
from pathlib import Path

path = Path("script/store_gmail_api_vault_credentials.rb")
src = path.read_text()

src = src.replace('sender = prompt("Authorized sender email")\n', '')
src = src.replace('    "sender" => sender\n', '')
src = src.replace('    "refresh_token" => refresh_token,\n    "sender" => sender\n',
                  '    "refresh_token" => refresh_token\n')

path.write_text(src)
print("Removed non-secret sender value from Vault payload.")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$FILE"

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git diff -- "$FILE"

echo
echo "=== STATUS ==="
git status --short
