#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

SERVICE="app/services/dymond_bank/stripe_service.rb"
READINESS="lib/tasks/susu_entitlements.rake"

[[ -f "$SERVICE" ]] || {
  echo "ERROR: missing $SERVICE"
  exit 1
}

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/host_stripe_vault_${STAMP}"
mkdir -p "$BACKUP"

for file in "$SERVICE" "$READINESS"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp "$file" "$BACKUP/$file"
  fi
done

python3 <<'PY'
from pathlib import Path
import re

path = Path("app/services/dymond_bank/stripe_service.rb")
src = path.read_text()

if "DymondBank::StripeCredentials.secret_key" in src:
    print("Host StripeService already uses StripeCredentials.")
    raise SystemExit(0)

pattern = re.compile(
    r'''      def configure!\n'''
    r'''        env_name =\n'''
    r'''          if DymondBank\.respond_to\?\(:configuration\) &&\n'''
    r'''             DymondBank\.configuration\.respond_to\?\(:stripe_secret_key_env\)\n'''
    r'''            DymondBank\.configuration\.stripe_secret_key_env\n'''
    r'''          else\n'''
    r'''            "STRIPE_SECRET_KEY"\n'''
    r'''          end\n'''
    r'''        key = ENV\[env_name\.to_s\]\.presence\n'''
    r'''        raise ConfigurationError, "#\{env_name\} is missing" if key\.blank\?\n'''
    r'''        Stripe\.api_key = key\n'''
    r'''      end'''
)

replacement = '''      def configure!
        key = DymondBank::StripeCredentials.secret_key
        raise ConfigurationError, "Stripe secret key is missing" if key.blank?

        Stripe.api_key = key
      end'''

if not pattern.search(src):
    raise SystemExit("ERROR: expected StripeService configure! block not found.")

path.write_text(pattern.sub(replacement, src, count=1))
print("Host StripeService now uses DymondBank::StripeCredentials.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("lib/tasks/susu_entitlements.rake")

if not path.exists():
    print("Susu readiness task not present; skipping.")
    raise SystemExit(0)

src = path.read_text()

old = '''    puts "Stripe mode:         #{ENV["STRIPE_SECRET_KEY"].to_s.start_with?("sk_live_") ? "live" : "test/non-live"}"
'''

new = '''    stripe_mode =
      begin
        DymondBank::StripeCredentials.secret_key.to_s.start_with?("sk_live_") ? "live" : "test/non-live"
      rescue StandardError => e
        "unavailable (#{e.class})"
      end

    puts "Stripe mode:         #{stripe_mode}"
'''

if new in src:
    print("Susu readiness already uses StripeCredentials.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Susu readiness now uses StripeCredentials.")
else:
    print("WARNING: expected Stripe mode line not found; readiness task unchanged.")
PY

echo
echo "=== GEM REVISION ==="
bundle info dymond_bank | head -n 5

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$SERVICE"
[[ ! -f "$READINESS" ]] || ruby -c "$READINESS"

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== CREDENTIAL SOURCE CHECK ==="
bin/rails runner '
puts "StripeCredentials loaded: #{!!defined?(DymondBank::StripeCredentials)}"
puts "Rails environment: #{Rails.env}"
puts "Credential source: #{Rails.env.production? ? "Lightek Vault" : "development/test ENV"}"
'

echo
echo "=== DIRECT STRIPE SECRET READS ==="
grep -RniE \
  'ENV\[.*STRIPE_(SECRET_KEY|WEBHOOK_SECRET|PUBLISHABLE_KEY)' \
  app lib config \
  --exclude-dir=tmp \
  || true

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git --no-pager diff -- \
  Gemfile.lock \
  "$SERVICE" \
  "$READINESS"

echo
echo "=== STATUS ==="
git status --short

echo
echo "HOST STRIPE VAULT WIRING COMPLETE"
echo "Backup: $BACKUP"
