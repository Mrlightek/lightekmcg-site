# frozen_string_literal: true

class Api::InstallationVoiceController < Api::ReservationFederationController
  before_action :require_installation_owner
  rescue_from LightekCommunications::InstallationVoice::Unavailable, LightekCommunications::VoiceSetup::Invalid,
    LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    with: ->(error) { render json: { error: error.message }, status: :unprocessable_entity }

  def status
    render json: LightekCommunications::InstallationVoice.new(@peer).status
  end

  def device
    response.headers["Cache-Control"] = "private, no-store"
    render json: LightekCommunications::InstallationVoice.new(@peer).device!
  end

  def checkout
    return head :payload_too_large if request.content_length.to_i > 3.megabytes

    setup = LightekCommunications::VoiceSetup
    fields = params.permit(:plan, number_request: %i[option area_code phone_number],
      voice_setup: [:confirm_emergency_address, :authorize_port, :document, { emergency: setup::ADDRESS_FIELDS, port: setup::PORT_FIELDS }])
    render json: LightekCommunications::InstallationVoice.new(@peer).checkout!(
      plan: fields[:plan].presence, number_request: fields.fetch(:number_request, {}).to_h, voice_setup: fields.fetch(:voice_setup, {}).to_h)
  end

  private

  def require_installation_owner
    head :forbidden unless params[:subject] == "owner"
  end
end
