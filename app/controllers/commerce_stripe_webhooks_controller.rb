# frozen_string_literal: true
class CommerceStripeWebhooksController < ActionController::Base
  protect_from_forgery with: :null_session
  def create
    secret = LightekCommerce::WebhookCredentials.secret
    return head :service_unavailable if secret.blank?
    event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], secret)
    LightekCommerce::StripeEvents.process!(event)
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  rescue LightekCommerce::WebhookCredentials::Unavailable, LightekVault::Crypto::DecryptionError, LightekVault::MasterKey::ConfigurationError
    head :service_unavailable
  rescue LightekCommerce::StripeEvents::Rejected => e
    Rails.logger.warn("[Commerce] rejected Stripe event: #{e.message}")
    head :unprocessable_entity
  ensure
    secret&.clear
  end
end
