# frozen_string_literal: true

require "base64"
require "google/apis/gmail_v1"
require "googleauth"

module LightekMail
  class GmailApiDelivery
    SCOPE = "https://www.googleapis.com/auth/gmail.send"

    attr_reader :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(mail)
      service = Google::Apis::GmailV1::GmailService.new
      service.client_options.application_name = "Lightek Mail"
      service.authorization = credentials

      # google-apis-core serializes Gmail's `raw` byte field for us.
      # Passing an already Base64URL-encoded string here double-encodes
      # the RFC 2822 message and prevents Gmail from seeing its headers.
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
