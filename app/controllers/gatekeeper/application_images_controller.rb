module Gatekeeper
  class ApplicationImagesController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create
    def create
      template = GatekeeperApplicationTemplate.find(params.require(:template_id))
      token = request.authorization.to_s.delete_prefix("Bearer ")
      claims = if template.build_identity.present?
        Hosting::GithubIdentity.verify!(token: token, identity: template.build_identity)
      else
        # Compatibility for builds dispatched before OIDC was deployed.
        expected = ENV["GATEKEEPER_FLEET_RELEASE_TOKEN"].to_s
        return head :service_unavailable if expected.blank?
        return head :unauthorized unless token.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(token, expected)
        nil
      end
      template.with_lock do
        if claims
          previous_run = template.build_identity["run_id"]
          return head :unauthorized if previous_run.present? && previous_run != claims["run_id"]
          template.update!(build_identity: template.build_identity.merge("run_id" => claims["run_id"]))
        end
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
    rescue Hosting::GithubIdentity::Invalid
      head :unauthorized
    rescue ArgumentError, ActiveRecord::RecordInvalid => error
      render json: {error: error.message}, status: :unprocessable_entity
    end
  end
end
