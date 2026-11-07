module Gatekeeper
  class ApplicationImagesController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create
    def create
      expected = ENV["GATEKEEPER_FLEET_RELEASE_TOKEN"].to_s
      return head :service_unavailable if expected.blank?
      token = request.authorization.to_s.delete_prefix("Bearer ")
      return head :unauthorized unless token.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, expected)
      template = GatekeeperApplicationTemplate.find(params.require(:template_id))
      template.with_lock do
        if params[:status] == "failed"
          template.update!(build_status: "failed", enabled: false) if template.build_status == "queued"
          return render json: {template_id: template.id, status: template.build_status}
        end
        image = params.require(:image).to_s
        raise ArgumentError, "Build is not pending" unless template.build_status == "queued" ||
          (template.build_status == "ready" && template.image == image)
        template.update!(image: image, build_status: "ready", enabled: true)
      end
      render json: {template_id: template.id}, status: :created
    rescue ArgumentError, ActiveRecord::RecordInvalid => error
      render json: {error: error.message}, status: :unprocessable_entity
    end
  end
end
