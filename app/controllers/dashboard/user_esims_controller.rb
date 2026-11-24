# frozen_string_literal: true

class Dashboard::UserEsimsController < ApplicationController
  protect_from_forgery with: :exception
  before_action :direct_session!
  before_action :require_platform_operator!, only: %i[create top_up set_status]

  rescue_from Telnyx::ProvisionEsimService::Invalid, Telnyx::ManageSimService::Invalid, ActiveRecord::RecordInvalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end
  rescue_from Telnyx::WirelessClient::Error do
    render json: { error: "Carrier update could not be confirmed" }, status: :bad_gateway
  end

  def show
    render json: summary(owned_esim)
  end

  def activation
    esim = owned_esim
    unless esim.activation_requested_at? && esim[:lpa_activation_code].present?
      return render json: { error: "The activation profile is still provisioning" }, status: :conflict
    end
    render json: {
      id: esim.id, apn: "data.net", lpa_activation_code: esim.lpa_activation_code,
      qr_png_base64: esim.activation_qr_base64
    }
  end

  def create
    data = params.require(:user_esim).permit(:user_id, :sim_card_group_id, :plan_limit_mb, :customer_wg_peer_ip)
    esim = Telnyx::ProvisionEsimService.call(user: User.find(data.fetch(:user_id)),
      sim_card_group_id: data.fetch(:sim_card_group_id), plan_limit_mb: data.fetch(:plan_limit_mb),
      customer_wg_peer_ip: data.fetch(:customer_wg_peer_ip), request_key: request.headers["Idempotency-Key"])
    render json: summary(esim), status: :accepted
  end

  def top_up
    esim = Telnyx::ManageSimService.new(UserEsim.find(params[:id])).top_up!(to_mb: params.require(:plan_limit_mb))
    render json: summary(esim)
  end

  def set_status
    esim = Telnyx::ManageSimService.new(UserEsim.find(params[:id])).set_status!(params.require(:status))
    render json: summary(esim), status: :accepted
  end

  private

  def direct_session!
    response.headers["Cache-Control"] = "private, no-store"
    head :forbidden unless current_user && Current.session.connect_delegation.blank?
  end

  def require_platform_operator!
    head :forbidden unless current_user.role == "super_admin"
  end

  def owned_esim
    UserEsim.where(user_id: current_user.id).find(params[:id])
  end

  def summary(esim)
    esim.as_json(only: %i[id status carrier_status plan_limit_mb assigned_private_ip])
  end
end
