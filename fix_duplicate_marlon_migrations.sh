#!/usr/bin/env bash
# The meta-framework installer WRITES migrations even with SKIP_MIGRATIONS=1
# (that flag only skips RUNNING db:migrate). Running it twice therefore wrote two
# sets with different timestamps but identical class names ->
#   ActiveRecord::DuplicateMigrationNameError: Multiple migrations have the name
#   CreateMarlonProjectTypes
#
# This keeps the OLDEST of each duplicate group and removes the rest. Nothing has
# migrated yet, so no data is at risk. macOS bash 3.2 safe.
#   cd ~/Desktop/Development/lightekmcg-site && bash fix_duplicate_marlon_migrations.sh
set -uo pipefail
echo "==> De-duplicating marlon migrations ($(pwd))"
[ -d "db/migrate" ] || { echo "  error: run from the Rails app root" >&2; exit 1; }

TRASH="tmp/marlon_dupe_migrations_$(date +%Y%m%d%H%M%S)"
mkdir -p "$TRASH"

# Group by migration CLASS name (the part after the timestamp), keep the oldest.
seen=""
removed=0
kept=0

for f in $(ls db/migrate/*_create_marlon_*.rb 2>/dev/null | sort); do
  base="$(basename "$f")"
  # strip leading timestamp_ -> create_marlon_project_types.rb
  name="${base#*_}"
  case " $seen " in
    *" $name "*)
      echo "  dupe  -> $base   (moving to $TRASH)"
      mv "$f" "$TRASH/"
      removed=$((removed+1))
      ;;
    *)
      echo "  keep  -> $base"
      seen="$seen $name"
      kept=$((kept+1))
      ;;
  esac
done

echo ""
echo "==> kept: $kept   removed: $removed   (moved, not deleted: $TRASH)"

if [ "$removed" -eq 0 ]; then
  echo "  nothing duplicated — if db:migrate still errors, paste the error."
fi

echo ""
echo "==> Confirm each marlon migration class appears exactly once:"
for f in db/migrate/*_create_marlon_*.rb; do
  [ -f "$f" ] || continue
  grep -h "^class " "$f"
done | sort | uniq -c | sed 's/^/    /'

echo ""
echo "==> NOW migrate + seed:"
echo "    bin/rails db:migrate"
echo "    bin/rails runner db/seeds/marlon_meta_framework.rb"
echo "    bin/rails runner 'p Marlon::ProjectType.pluck(:key)'"
echo ""
echo "==> Optional: clear the installer's .bak clutter (Zeitwerk ignores them,"
echo "   they just aren't pretty):"
echo "    find app lib db config docs -name '*.bak.2026*' -print"
echo "    # then, if you're happy:  find app lib db config docs -name '*.bak.2026*' -delete"
