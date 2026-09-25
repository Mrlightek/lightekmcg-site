#!/usr/bin/env bash
set -euo pipefail

OLD=".github/workflows/docker-image.yml"
DEST_DIR=".github/disabled-workflows"
DEST="$DEST_DIR/docker-image.yml"

if [[ ! -f "$OLD" ]]; then
  echo "Old Docker workflow not found at $OLD"
  echo "Nothing to disable."
  exit 0
fi

mkdir -p "$DEST_DIR"

STAMP="$(date +%Y%m%d%H%M%S)"
cp "$OLD" "${OLD}.backup.${STAMP}"

mv "$OLD" "$DEST"

echo
echo "Disabled old Docker image workflow."
echo "Moved:"
echo "  $OLD"
echo "to:"
echo "  $DEST"
echo
echo "GitHub Actions will no longer auto-run that Docker build because"
echo "the file is no longer under .github/workflows/."
echo
echo "Current workflow files:"
find .github/workflows -maxdepth 1 -type f -print | sort || true

echo
echo "Next:"
echo "  git add -A"
echo '  git commit -m "Disable obsolete Docker image workflow"'
echo "  git push origin main"
