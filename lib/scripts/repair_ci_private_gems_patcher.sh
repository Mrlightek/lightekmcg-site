#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

WORKFLOW="${2:-.github/workflows/ci.yml}"

[[ -f "$WORKFLOW" ]] || {
  echo "ERROR: CI workflow not found: $WORKFLOW"
  exit 1
}

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
i = 0

while i < len(lines):
    line = lines[i]

    # Match the named setup step:
    #       - name: Set up Ruby
    #         uses: ruby/setup-ruby@v1
    m = re.match(r'^(\s*)-\s+name:\s+Set up Ruby\s*$', line.rstrip("\n"))
    if m and i + 1 < len(lines):
        indent = m.group(1)
        next_line = lines[i + 1]

        if re.match(rf'^{re.escape(indent)}\s{{2}}uses:\s+ruby/setup-ruby@', next_line):
            block = [
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
                f'{indent}    echo "Configured Lightek private dependency authentication."\n',
                "\n",
            ]
            out.extend(block)
            insertions += 1

    out.append(line)
    i += 1

if insertions == 0:
    raise SystemExit("ERROR: no named 'Set up Ruby' step followed by ruby/setup-ruby was found.")

path.write_text("".join(out))
print(f"Inserted Lightek private dependency authentication before {insertions} Ruby setup step(s).")
PY

echo
echo "=== VERIFY INSERTIONS ==="
grep -n -A16 -B2 'Create Lightek private dependency token' "$WORKFLOW" || true

echo
echo "=== RUBY SETUP COUNT ==="
SETUP_COUNT="$(grep -c 'uses: ruby/setup-ruby@' "$WORKFLOW" || true)"
TOKEN_COUNT="$(grep -c 'name: Create Lightek private dependency token' "$WORKFLOW" || true)"
echo "ruby/setup-ruby steps: $SETUP_COUNT"
echo "auth token steps:      $TOKEN_COUNT"

if [[ "$SETUP_COUNT" -ne "$TOKEN_COUNT" ]]; then
  echo "ERROR: auth step count does not match Ruby setup step count."
  exit 1
fi

echo
echo "=== DIFF CHECK ==="
git diff --check -- "$WORKFLOW"

echo
echo "Patch complete."
echo "Backup:"
echo "  $BACKUP"
echo
echo "Next:"
echo "  1. Create/install the Lightek CI Dependencies GitHub App."
echo "  2. Add repo Actions secrets:"
echo "       LIGHTEK_CI_APP_ID"
echo "       LIGHTEK_CI_APP_PRIVATE_KEY"
echo "  3. Then:"
echo "       git add $WORKFLOW"
echo '       git commit -m "Authenticate CI to Lightek private dependencies"'
echo "       git push origin main"
