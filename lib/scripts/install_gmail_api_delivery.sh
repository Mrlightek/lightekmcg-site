#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gmail_api_delivery_${STAMP}"

mkdir -p \
  "$BACKUP/app/services/lightek_mail" \
  "$BACKUP/config/initializers" \
  app/services/lightek_mail \
  config/initializers

backup() {
  local file="$1"

  if [[ -f "$file" ]]; then
    mkdir -p "$BACKUP/$(dirname "$file")"
    cp "$file" "$BACKUP/$file"
  fi
}

backup Gemfile
backup Gemfile.lock
backup app/services/lightek_mail/gmail_api_delivery.rb
backup config/initializers/gmail_api_delivery.rb

echo "==> Ensuring Gmail API gems"

if ! grep -Eq 'gem ["'\'']google-apis-gmail_v1["'\'']' Gemfile; then
  bundle add google-apis-gmail_v1
else
  echo "google-apis-gmail_v1 already present."
fi

if ! grep -Eq 'gem ["'\'']googleauth["'\'']' Gemfile; then
  bundle add googleauth
else
  echo "googleauth already present."
fi

echo
echo "==> Installing Gmail API delivery method"

cat > app/services/lightek_mail/gmail_api_delivery.rb <<'RUBY'
# frozen_string_literal: true

require "base64"
require "google/apis/gmail_v1"
require "googleauth"

module LightekMail
  class GmailApiDelivery
    SCOPE = "https://www.googleapis.com/auth/gmail.send"

    def initialize(_settings = {})
    end

    def deliver!(mail)
      service = Google::Apis::GmailV1::GmailService.new
      service.client_options.application_name = "Lightek Mail"
      service.authorization = credentials

      raw_message = Base64.urlsafe_encode64(
        mail.to_s,
        padding: false
      )

      gmail_message = Google::Apis::GmailV1::Message.new(
        raw: raw_message
      )

      result = service.send_user_message("me", gmail_message)

      Rails.logger.info(
        "[LightekMail::GmailApiDelivery] sent gmail_message_id=#{result.id}"
      )

      result
    end

    private

    def credentials
      credentials = Google::Auth::UserRefreshCredentials.new(
        client_id: ENV.fetch("GOOGLE_GMAIL_CLIENT_ID"),
        client_secret: ENV.fetch("GOOGLE_GMAIL_CLIENT_SECRET"),
        scope: SCOPE,
        refresh_token: ENV.fetch("GOOGLE_GMAIL_REFRESH_TOKEN")
      )

      credentials.fetch_access_token!
      credentials
    end
  end
end
RUBY

cat > config/initializers/gmail_api_delivery.rb <<'RUBY'
# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActionMailer::Base.add_delivery_method(
    :gmail_api,
    LightekMail::GmailApiDelivery
  )
end
RUBY

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/services/lightek_mail/gmail_api_delivery.rb
ruby -c config/initializers/gmail_api_delivery.rb

echo
echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo
echo "=== DELIVERY METHOD REGISTRATION ==="
bin/rails runner '
puts "gmail_api registered=#{ActionMailer::Base.delivery_methods.key?(:gmail_api)}"
puts "delivery methods=#{ActionMailer::Base.delivery_methods.keys.sort.inspect}"
'

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git diff -- \
  Gemfile \
  Gemfile.lock \
  app/services/lightek_mail/gmail_api_delivery.rb \
  config/initializers/gmail_api_delivery.rb

echo
echo "=== STATUS ==="
git status --short

echo
echo "GMAIL API DELIVERY INSTALL COMPLETE"
echo "Backup: $BACKUP"
