#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

FILE="config/environments/production.rb"
STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/production_gmail_api_mail_${STAMP}"

[[ -f "$FILE" ]] || {
  echo "ERROR: missing $FILE"
  exit 1
}

mkdir -p "$BACKUP/$(dirname "$FILE")"
cp "$FILE" "$BACKUP/$FILE"

python3 <<'PY'
from pathlib import Path

path = Path("config/environments/production.rb")
src = path.read_text()

old = '''  # SUSU SMTP CONFIGURATION
  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS"),
      port: ENV.fetch("SMTP_PORT", "587").to_i,
      domain: ENV.fetch("SMTP_DOMAIN", "lightekmcg.com"),
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain"),
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
    }
    config.action_mailer.default_url_options = {
      host: ENV.fetch("APP_HOST", "lightekmcg.com"),
      protocol: ENV.fetch("APP_PROTOCOL", "https")
    }
  end
'''

new = '''  # SUSU / TRANSACTIONAL MAIL DELIVERY
  #
  # Preferred path while Linode SMTP egress is restricted:
  # Gmail API over HTTPS using OAuth refresh credentials.
  #
  # SMTP remains available as a fallback for later.
  if ENV["GOOGLE_GMAIL_REFRESH_TOKEN"].present?
    config.action_mailer.delivery_method = :gmail_api
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
  elsif ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SMTP_ADDRESS"),
      port: ENV.fetch("SMTP_PORT", "587").to_i,
      domain: ENV.fetch("SMTP_DOMAIN", "lightekmcg.com"),
      user_name: ENV["SMTP_USERNAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain"),
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true"
    }
  end

  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "lightekmcg.com"),
    protocol: ENV.fetch("APP_PROTOCOL", "https")
  }
'''

if new in src:
    print("Production Gmail API mail delivery already installed.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Installed Gmail API production mail delivery with SMTP fallback.")
else:
    raise SystemExit("ERROR: expected production SMTP block not found")
PY

echo
echo "=== RUBY SYNTAX ==="
ruby -c "$FILE"

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git diff -- "$FILE"

echo
echo "=== STATUS ==="
git status --short

echo
echo "PRODUCTION GMAIL API MAIL DELIVERY INSTALL COMPLETE"
echo "Backup: $BACKUP"
