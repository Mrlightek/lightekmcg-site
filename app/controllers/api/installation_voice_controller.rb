# frozen_string_literal: true

class Api::InstallationVoiceController < Api::ReservationFederationController
  before_action :require_installation_owner
  rescue_from LightekCommunications::InstallationVoice::Unavailable,
    LightekCommerce::OrderPlacement::Invalid, LightekCommerce::StripeCheckout::Unavailable,
    with: ->(error) { render json: { error: error.message }, status: :unprocessable_entity }

  def status
    render json: LightekCommunications::InstallationVoice.new(@peer).status
  end

  def checkout
    fields = params.permit(:plan, number_request: %i[option area_code phone_number])
    render json: LightekCommunications::InstallationVoice.new(@peer).checkout!(
      plan: fields[:plan].presence, number_request: fields.fetch(:number_request, {}).to_h)
  end

  private

  def require_installation_owner
    head :forbidden unless params[:subject] == "owner"
  end
end
