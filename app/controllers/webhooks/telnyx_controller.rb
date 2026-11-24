# frozen_string_literal: true

module Webhooks
  class TelnyxController < ActionController::Base
    protect_from_forgery with: :exception
    skip_before_action :verify_authenticity_token

    EVENTS = %w[
      sim_card.status_changed sim_card.status.changed
      sim_card.data_usage_limit.reached sim_card.data_usage_limit_reached
    ].freeze
    MAX_BODY = 256.kilobytes

    def create
      return head :payload_too_large if request.content_length.to_i > MAX_BODY
      body = request.raw_post
      return head :payload_too_large if body.bytesize > MAX_BODY
      unless Telnyx::WebhookSignature.valid?(timestamp: request.headers["telnyx-timestamp"],
          signature: request.headers["telnyx-signature-ed25519"], body: body)
        return head :unauthorized
      end

      event = JSON.parse(body)["data"]
      return head :bad_request unless event.is_a?(Hash)
      return head :no_content unless EVENTS.include?(event["event_type"])

      payload = event["payload"]
      return head :bad_request unless payload.is_a?(Hash)
      sim_id = payload["sim_card_id"] || payload.dig("sim_card", "id") || payload["id"]
      return head :bad_request unless UserEsim::UUID.match?(sim_id.to_s) && UserEsim::UUID.match?(event["id"].to_s)

      esim = UserEsim.find_by(telnyx_sim_id: sim_id)
      SyncEsimStatusJob.perform_later(esim.id, event["id"]) if esim
      head :no_content
    rescue JSON::ParserError, TypeError
      head :bad_request
    end
  end
end
