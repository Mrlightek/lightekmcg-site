# frozen_string_literal: true
class GatekeeperController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session, except: :device_api
  before_action :build_experience, only: %i[index platform_config content live search]
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rescue_from ActiveRecord::RecordNotFound do
    render json: {error: "Application or content not found"}, status: :not_found
  end
  rescue_from ArgumentError do |error|
    render json: {error: error.message}, status: :unprocessable_entity
  end
  def index = render(json: @experience.home)
  def platform_config = render(json: @experience.config)
  def content = render(json: @experience.content(params[:id]))
  def live = render(json: @experience.home(live: true))
  def search = render(json: @experience.home(query: params[:q].presence || params[:query]))
  def permitted_actions = %w[device_enroll device_heartbeat device_maintenance_claim device_maintenance_report]
  def request_error_message = {error: "Invalid or unauthorized method type"}
  # Explicit Gatekeeper device API dispatcher. Never dynamically dispatch arbitrary
  # controller methods supplied by the client.
  def device_api
    action = params[:method_type].to_s
    unless permitted_actions.include?(action)
      return render json: { error: "Action not permitted" }, status: :bad_request
    end

    device = NetworkManagedDevice.find_by(identifier: params[:identifier].to_s)
    return render json: { error: "Device not registered" }, status: :unauthorized unless device

    token = request.authorization.to_s.delete_prefix("Bearer ").strip
    unless request.authorization.to_s.start_with?("Bearer ") && device.authenticate_enrollment_token?(token)
      return render json: { error: "Invalid device credentials" }, status: :unauthorized
    end

    device.with_lock do
      if device.status == "retired"
        render json: { error: "Device retired" }, status: :forbidden
      elsif device.authenticate_enrollment_token?(token)
        perform_device_action(device, action)
      else
        render json: { error: "Invalid device credentials" }, status: :unauthorized
      end
    end
  end

  def perform_device_action(device, action)
    case action
    when "device_enroll"
      return render json: { error: "Device is suspended" }, status: :forbidden if device.status == "maintenance"
      device.update!(enrolled_at: Time.current, last_seen_at: Time.current,
        last_heartbeat_ip: request.remote_ip, status: "active")
      render json: { ok: true, device_id: device.id, status: device.status }
    when "device_maintenance_report"
      return render json: { error: "Monitoring not enabled" }, status: :forbidden unless
        device.owner_id.present? && device.managed_monitoring_enabled? && device.enrolled_at.present? &&
        device.status == "active"
      begin
        raw = params.require(:result)
        raise ArgumentError, "Result must be an object" unless raw.is_a?(ActionController::Parameters)
        record = ItServices::EndpointMaintenance.report!(device: device,
          action_id: Integer(params.require(:action_id)),
          nonce: params.require(:nonce).to_s,
          result: raw.to_unsafe_h)
        render json: { ok: true, action_id: record.id, status: record.status }
      rescue ArgumentError, ActionController::ParameterMissing => error
        render json: { error: error.message }, status: :unprocessable_entity
      end
    when "device_maintenance_claim"
      action_id = Integer(params.require(:action_id))
      record = ItServices::EndpointMaintenance.claim!(device: device,
        action_id: action_id, nonce: params.require(:nonce).to_s)
      render json: { ok: true, action_id: record.id, patch_target: record.patch_target,
        restore_digest: (record.expected_recovery_digest if record.staged_restore? || record.live_restore?) }.compact
    when "device_heartbeat"
      return render json: { error: "Enrollment required" }, status: :forbidden unless device.enrolled_at?
      return render json: { error: "Device is not active" }, status: :forbidden unless %w[active offline].include?(device.status)
      begin
        if params.key?(:health_telemetry)
          raw = params[:health_telemetry]
          raise ArgumentError, "Telemetry must be an object" unless raw.is_a?(ActionController::Parameters)
          data = ItServices::DeviceTelemetry.normalize!(raw.to_unsafe_h)
          raise ArgumentError, "Device owner and enrollment required for telemetry" unless device.owner_id.present?
          if device.managed_monitoring_enabled? && LightekPeople::LifecycleAccess.active?(device.owner)
            device.health_telemetry = data
            device.health_telemetry_at = Time.current
          end
        end
        device.update!(last_seen_at: Time.current, last_heartbeat_ip: request.remote_ip, status: "active")
      rescue ArgumentError => error
        return render json: { error: error.message }, status: :unprocessable_entity
      end
      render json: { ok: true, device_id: device.id, status: device.status,
        server_time: Time.current.iso8601,
        maintenance_actions: device.managed_monitoring_enabled? ?
          ItServices::EndpointMaintenance.pending_for!(device: device) : [] }
    end
  end
  private :perform_device_action

  # Legacy Octavia dispatcher: allowlist is evaluated as data, never as a
  # method name or dynamic controller target.
  def octavia
    action = params[:method_type].to_s
    return render json: request_error_message, status: :bad_request unless permitted_actions.include?(action)
    return render json: { error: "Use the device API endpoint" }, status: :bad_request if action.start_with?("device_")
    render json: { error: "Unsupported action" }, status: :bad_request
  end


  private
  def build_experience
    site = LightekPwa::SiteContext.resolve(request.host)
    platform = params[:platform].presence || "roku"
    viewing_user = Studio::Advertising::ViewingLink.viewer(site: site, authorization: request.authorization) if platform == "roku"
    @experience = Studio::Broadcasting::Experience.new(site: site, user: current_user,
      platform: platform, slug: params[:application], origin: request.base_url, viewing_user: viewing_user, viewing_links: request.headers["X-Lightek-Viewing-Link"] == "1")
  end
end
