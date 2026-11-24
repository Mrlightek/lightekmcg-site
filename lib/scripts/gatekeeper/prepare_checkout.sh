#!/usr/bin/env bash
# Preserve generated Rails and Bundler files before updating a deployed checkout.
set -euo pipefail
: "${1:?Supply the application checkout path}"
cd -- "$1"
git rev-parse --show-toplevel >/dev/null

dirty=()
for path in db/schema.rb Gemfile.lock; do
  git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || continue
  if ! git diff --cached --quiet -- "$path"; then
    echo "ERROR: staged changes to $path require review; checkout left unchanged." >&2
    exit 1
  fi
  git diff --quiet -- "$path" && continue
  if [[ -L "$path" || ( -e "$path" && ! -f "$path" ) ]]; then
    echo "ERROR: $path is not a regular file; checkout left unchanged." >&2
    exit 1
  fi
  dirty+=("$path")
done

[[ ${#dirty[@]} -gt 0 ]] || exit 0
umask 077
mkdir -p tmp/deploy-backups
backup_dir=$(mktemp -d "$(pwd)/tmp/deploy-backups/generated-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")

for path in "${dirty[@]}"; do
  name=${path##*/}
  git diff --no-ext-diff --binary -- "$path" > "$backup_dir/${name%.rb}.patch"
  if [[ -f "$path" ]]; then
    cp -- "$path" "$backup_dir/$name"
    cmp -- "$path" "$backup_dir/$name"
  fi
done

git restore --source=HEAD --worktree -- "${dirty[@]}"
echo "Generated checkout files backed up to $backup_dir before checkout update."
