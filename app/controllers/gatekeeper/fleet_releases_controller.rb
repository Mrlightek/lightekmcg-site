module Gatekeeper
  class FleetReleasesController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create

    def create
      expected = ENV["GATEKEEPER_FLEET_RELEASE_TOKEN"].to_s
      return head :service_unavailable if expected.blank?
      token = request.authorization.to_s.delete_prefix("Bearer ")
      return head :unauthorized unless token.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      payload = params.require(:release).permit(:version, :source_sha, :image, :notes, :channel, :backward_compatible, :adapter, :component, :repository).to_h
      release = Fleet::Releases.register!(payload)
      render json: {release_id: release.id, version: release.version}, status: :created
    rescue ArgumentError, KeyError, ActiveRecord::RecordInvalid, Fleet::Rollouts::Invalid => error
      render json: {error: error.message}, status: :unprocessable_entity
    end
  end
end
