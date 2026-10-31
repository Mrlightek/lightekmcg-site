#!/usr/bin/env bash
# Preserve only Rails' generated schema before updating a deployed checkout.
set -euo pipefail
: "${1:?Supply the application checkout path}"
cd -- "$1"
git rev-parse --show-toplevel >/dev/null
schema=db/schema.rb
git ls-files --error-unmatch -- "$schema" >/dev/null 2>&1 || exit 0
if ! git diff --cached --quiet -- "$schema"; then
  echo 'ERROR: staged schema changes require review; checkout left unchanged.' >&2
  exit 1
fi
git diff --quiet -- "$schema" && exit 0
[[ ! -L "$schema" ]] || { echo 'ERROR: schema is a symbolic link; checkout left unchanged.' >&2; exit 1; }
umask 077
mkdir -p tmp/deploy-backups
backup_dir=$(mktemp -d "$(pwd)/tmp/deploy-backups/schema-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
git diff --binary -- "$schema" > "$backup_dir/schema.patch"
if [[ -f "$schema" ]]; then
  cp -- "$schema" "$backup_dir/schema.rb"
  cmp -- "$schema" "$backup_dir/schema.rb"
fi
git restore --source=HEAD --worktree -- "$schema"
echo "Generated schema backed up to $backup_dir before checkout update."
