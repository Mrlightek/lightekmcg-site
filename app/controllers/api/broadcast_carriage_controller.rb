# frozen_string_literal: true

class Api::BroadcastCarriageController < Api::ReservationFederationController
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: "That carriage reference already exists." }, status: :conflict
  end

  def save
    values = params.permit(:name, :description, :published, :withdrawn, :renew, schedule: %i[title starts_at ends_at on_air]).to_h
    render json: Studio::Broadcasting::InstallationCarriage.receive!(@peer, params[:key], values)
  end
end
