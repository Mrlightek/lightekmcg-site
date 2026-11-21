# frozen_string_literal: true

class Api::BroadcastCarriageController < Api::ReservationFederationController
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: "That carriage reference already exists." }, status: :conflict
  end

  def save
    values = params.permit(:name, :description, :published, :withdrawn, :renew, schedule: %i[title starts_at ends_at on_air]).to_h
    render json: Studio::Broadcasting::InstallationCarriage.receive!(@peer, params[:key], values)
  end

  def agreements
    render json: { agreements: hosted_agreements.includes(:outlet_site, :hosted_carriage).order(id: :desc).limit(100).map(&:station_receipt) }
  end

  def accept_agreement
    agreement = hosted_agreements.find(params[:id])
    agreement.accept_from_peer!(@peer)
    render json: agreement.station_receipt
  end

  private

  def hosted_agreements
    Studio::Broadcasting::CarriageAgreement.where(station_site_id: @peer.site_id,
      hosted_carriage_id: Studio::Broadcasting::HostedCarriage.where(peer: @peer).select(:id))
  end
end
