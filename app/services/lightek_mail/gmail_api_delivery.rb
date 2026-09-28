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
