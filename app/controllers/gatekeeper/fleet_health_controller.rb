module Gatekeeper
  class FleetHealthController < ApplicationController
    allow_unauthenticated_access only: :show
    def show
      response.headers["Cache-Control"] = "no-store"
      sha = Rails.application.config.x.fleet_boot_revision
      return head :service_unavailable if sha.blank?
      render json: {source_sha: sha, component: "lightek_app"}
    end
  end
end
