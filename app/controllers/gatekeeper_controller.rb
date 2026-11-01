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
  def permitted_actions = %w[device_enroll device_heartbeat]
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
    return render json: { error: "Device retired" }, status: :forbidden if device.status == "retired"

    token = request.authorization.to_s.delete_prefix("Bearer ").strip
    unless request.authorization.to_s.start_with?("Bearer ") && device.authenticate_enrollment_token?(token)
      return render json: { error: "Invalid device credentials" }, status: :unauthorized
    end

    case action
    when "device_enroll"
      return render json: { error: "Device is suspended" }, status: :forbidden if device.status == "maintenance"
      device.update!(enrolled_at: Time.current, last_seen_at: Time.current,
        last_heartbeat_ip: request.remote_ip, status: "active")
      render json: { ok: true, device_id: device.id, status: device.status }
    when "device_heartbeat"
      return render json: { error: "Enrollment required" }, status: :forbidden unless device.enrolled_at?
      return render json: { error: "Device is not active" }, status: :forbidden unless %w[active offline].include?(device.status)
      device.update!(last_seen_at: Time.current, last_heartbeat_ip: request.remote_ip,
        status: "active")
      render json: { ok: true, device_id: device.id, status: device.status,
        server_time: Time.current.iso8601 }
    end
  end

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
    @experience = Studio::Broadcasting::Experience.new(site: site, user: current_user,
      platform: params[:platform].presence || "roku", slug: params[:application], origin: request.base_url)
  end
end
