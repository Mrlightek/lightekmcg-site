#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

if [[ ! -d .github/workflows ]]; then
  echo "ERROR: .github/workflows not found. Run from the Rails repo root."
  exit 1
fi

WORKFLOW="${2:-}"

if [[ -z "$WORKFLOW" ]]; then
  for candidate in     .github/workflows/ci.yml     .github/workflows/ci.yaml     .github/workflows/test.yml     .github/workflows/test.yaml
  do
    if [[ -f "$candidate" ]]; then
      WORKFLOW="$candidate"
      break
    fi
  done
fi

if [[ -z "$WORKFLOW" || ! -f "$WORKFLOW" ]]; then
  echo "ERROR: could not find the CI workflow automatically."
  echo "Usage:"
  echo "  bash $0 . .github/workflows/<your-ci-file>.yml"
  exit 1
fi

if ! grep -q 'ruby/setup-ruby@' "$WORKFLOW"; then
  echo "ERROR: $WORKFLOW does not contain ruby/setup-ruby."
  exit 1
fi

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="${WORKFLOW}.backup.${STAMP}"
cp "$WORKFLOW" "$BACKUP"

python3 - "$WORKFLOW" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

if "LIGHTEK_CI_APP_ID" in src and "Configure Lightek private dependency access" in src:
    print("CI workflow already contains Lightek private dependency authentication.")
    sys.exit(0)

lines = src.splitlines(True)
out = []
insertions = 0

for line in lines:
    m = re.match(r'^(\s*)-\s+uses:\s+ruby/setup-ruby@', line)
    if m:
        indent = m.group(1)
        block_lines = [
            f"{indent}- name: Create Lightek private dependency token\n",
            f"{indent}  id: lightek_private_repos\n",
            f"{indent}  uses: actions/create-github-app-token@v2\n",
            f"{indent}  with:\n",
            f"{indent}    app-id: ${{{{ secrets.LIGHTEK_CI_APP_ID }}}}\n",
            f"{indent}    private-key: ${{{{ secrets.LIGHTEK_CI_APP_PRIVATE_KEY }}}}\n",
            f"{indent}    owner: lightekmcg\n",
            "\n",
            f"{indent}- name: Configure Lightek private dependency access\n",
            f"{indent}  shell: bash\n",
            f"{indent}  env:\n",
            f"{indent}    LIGHTEK_GITHUB_TOKEN: ${{{{ steps.lightek_private_repos.outputs.token }}}}\n",
            f"{indent}  run: |\n",
            f"{indent}    set -euo pipefail\n",
            f'{indent}    git config --global --add url."https://x-access-token:${{LIGHTEK_GITHUB_TOKEN}}@github.com/".insteadOf "git@github.com:"\n',
            f'{indent}    git config --global --add url."https://x-access-token:${{LIGHTEK_GITHUB_TOKEN}}@github.com/".insteadOf "ssh://git@github.com/"\n',
            f'{indent}    echo "Configured read-only GitHub App authentication for Lightek private dependencies."\n',
            "\n",
        ]
        out.extend(block_lines)
        insertions += 1

    out.append(line)

if insertions == 0:
    raise SystemExit("ERROR: no ruby/setup-ruby step was found to patch.")

path.write_text("".join(out))
print(f"Inserted private dependency authentication before {insertions} ruby/setup-ruby step(s).")
PY

echo
echo "=== PATCHED WORKFLOW ==="
grep -n -A16 -B2 'Create Lightek private dependency token' "$WORKFLOW" || true

echo
echo "=== PRIVATE GIT DEPENDENCIES ==="
grep -nE 'git@github\.com:lightekmcg/' Gemfile || true

echo
echo "=== DIFF CHECK ==="
git diff --check -- "$WORKFLOW"

echo
echo "Patched CI private dependency authentication."
echo "Backup:"
echo "  $BACKUP"
echo
echo "GitHub setup required ONCE:"
echo "  1. Create a GitHub App named something like: Lightek CI Dependencies"
echo "  2. Repository permission: Contents = Read-only"
echo "  3. Install it on the private dependency repositories"
echo "  4. Add these Actions secrets to this repo:"
echo "       LIGHTEK_CI_APP_ID"
echo "       LIGHTEK_CI_APP_PRIVATE_KEY"
echo
echo "Private repos currently referenced by Gemfile:"
grep -oE 'git@github\.com:lightekmcg/[A-Za-z0-9_.-]+' Gemfile   | sed 's#git@github.com:lightekmcg/#  - #'   | sort -u || true
echo
echo "Then:"
echo "  git add $WORKFLOW"
echo '  git commit -m "Authenticate CI to Lightek private dependencies"'
echo "  git push origin main"
