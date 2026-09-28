#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gmail_vault_integration_${STAMP}"

FILES=(
  "app/services/lightek_mail/gmail_api_delivery.rb"
  "config/environments/production.rb"
  "script/store_gmail_api_vault_credentials.rb"
)

mkdir -p "$BACKUP"

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp "$file" "$BACKUP/$file"
  fi
done

echo "==> Routing Gmail API delivery through Lightek Vault"

mkdir -p app/services/lightek_mail

cat > app/services/lightek_mail/gmail_api_delivery.rb <<'RUBY'
# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"

module LightekMail
  class GmailApiDelivery
    SCOPE = "https://www.googleapis.com/auth/gmail.send"
    DEFAULT_VAULT_SLUG = "gmail-api-production"
    CONSUMER = name
    PURPOSE = "transactional_mail"

    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      payload = vault_payload

      service = Google::Apis::GmailV1::GmailService.new
      service.client_options.application_name = "Lightek Mail"
      service.authorization = google_credentials(payload)

      gmail_message = Google::Apis::GmailV1::Message.new(
        raw: mail.encoded
      )

      result = service.send_user_message("me", gmail_message)

      Rails.logger.info(
        "[LightekMail::GmailApiDelivery] sent gmail_message_id=#{result.id}"
      )

      result
    end

    private

    def vault_payload
      LightekVault::Service.checkout!(
        slug: vault_slug,
        consumer: CONSUMER,
        purpose: PURPOSE,
        requested_by: "lightek-mail"
      )
    end

    def vault_slug
      settings[:vault_slug].presence ||
        ENV.fetch("GMAIL_API_VAULT_SLUG", DEFAULT_VAULT_SLUG)
    end

    def google_credentials(payload)
      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: payload.fetch("client_id"),
        client_secret: payload.fetch("client_secret"),
        refresh_token: payload.fetch("refresh_token"),
        scope: SCOPE
      )

      credentials.fetch_access_token!
      credentials
    end
  end
end
RUBY

echo "==> Updating production mail selection"

python3 <<'PY'
from pathlib import Path
import re

path = Path("config/environments/production.rb")
src = path.read_text()

pattern = re.compile(
    r'''  # SUSU / TRANSACTIONAL MAIL DELIVERY.*?'''
    r'''  config\.action_mailer\.default_url_options = \{\n'''
    r'''    host: ENV\.fetch\("APP_HOST", "lightekmcg\.com"\),\n'''
    r'''    protocol: ENV\.fetch\("APP_PROTOCOL", "https"\)\n'''
    r'''  \}\n''',
    re.S
)

replacement = '''  # SUSU / TRANSACTIONAL MAIL DELIVERY
  #
  # Secret material is retrieved by the delivery adapter from Lightek Vault.
  # MAIL_DELIVERY_METHOD is configuration only; it contains no credentials.
  case ENV.fetch("MAIL_DELIVERY_METHOD", "gmail_api")
  when "gmail_api"
    config.action_mailer.delivery_method = :gmail_api
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
  when "smtp"
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
  else
    raise ArgumentError,
          "Unsupported MAIL_DELIVERY_METHOD: #{ENV['MAIL_DELIVERY_METHOD'].inspect}"
  end

  config.action_mailer.default_url_options = {
    host: ENV.fetch("APP_HOST", "lightekmcg.com"),
    protocol: ENV.fetch("APP_PROTOCOL", "https")
  }
'''

updated, count = pattern.subn(replacement, src, count=1)

if count == 0:
    if replacement in src:
        print("Production Vault mail configuration already installed.")
    else:
        raise SystemExit(
            "ERROR: expected transactional mail configuration block not found"
        )
else:
    path.write_text(updated)
    print("Production mail configuration updated.")
PY

echo "==> Installing secure Vault credential loader"

cat > script/store_gmail_api_vault_credentials.rb <<'RUBY'
# frozen_string_literal: true

require "io/console"

SLUG = ENV.fetch("GMAIL_API_VAULT_SLUG", "gmail-api-production")

def prompt(label, secret: false)
  print "#{label}: "

  value =
    if secret
      STDIN.noecho(&:gets).to_s
    else
      STDIN.gets.to_s
    end

  puts if secret

  value.strip
end

puts
puts "=== LIGHTEK VAULT · GMAIL API CREDENTIAL STORAGE ==="
puts
puts "Secret values will not be echoed or written to this script."
puts

client_id = prompt("Google OAuth client ID")
client_secret = prompt("Google OAuth client secret", secret: true)
refresh_token = prompt("Google OAuth refresh token", secret: true)
sender = prompt("Authorized sender email")

{
  "client_id" => client_id,
  "client_secret" => client_secret,
  "refresh_token" => refresh_token,
  "sender" => sender
}.each do |key, value|
  abort "#{key} cannot be blank" if value.empty?
end

secret = LightekVault::Service.store!(
  name: "Google Gmail API Production",
  slug: SLUG,
  payload: {
    "client_id" => client_id,
    "client_secret" => client_secret,
    "refresh_token" => refresh_token,
    "sender" => sender
  },
  secret_type: "credential",
  provider: "google",
  environment: "production",
  purpose: "transactional_mail",
  access_policy: {
    "consumers" => [
      "LightekMail::GmailApiDelivery"
    ],
    "purposes" => [
      "transactional_mail"
    ]
  },
  metadata: {
    "service" => "gmail_api",
    "scope" => "https://www.googleapis.com/auth/gmail.send"
  },
  requested_by: "operator"
)

puts
puts "GMAIL API VAULT SECRET STORED"
puts "slug=#{secret.slug}"
puts "provider=#{secret.provider}"
puts "environment=#{secret.environment}"
puts "status=#{secret.status}"
puts
puts "Plaintext credentials were not redisplayed."
RUBY

chmod +x script/store_gmail_api_vault_credentials.rb

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/services/lightek_mail/gmail_api_delivery.rb
ruby -c config/environments/production.rb
ruby -c script/store_gmail_api_vault_credentials.rb

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== ENV CREDENTIAL BYPASS CHECK ==="

if grep -nE \
  'ENV\.(fetch|\[)\("?GOOGLE_GMAIL_(CLIENT_ID|CLIENT_SECRET|REFRESH_TOKEN)' \
  app/services/lightek_mail/gmail_api_delivery.rb \
  config/environments/production.rb
then
  echo
  echo "ERROR: direct Gmail credential ENV lookup still exists."
  exit 1
else
  echo "PASS: Gmail delivery no longer reads OAuth secrets from ENV."
fi

echo
echo "=== TARGETED DIFF ==="
git diff -- \
  app/services/lightek_mail/gmail_api_delivery.rb \
  config/environments/production.rb \
  script/store_gmail_api_vault_credentials.rb

echo
echo "=== STATUS ==="
git status --short

echo
echo "GMAIL -> LIGHTEK VAULT INTEGRATION COMPLETE"
echo "Backup: $BACKUP"
