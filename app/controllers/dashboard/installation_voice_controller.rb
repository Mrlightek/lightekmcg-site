# frozen_string_literal: true

require "base64"

class Dashboard::InstallationVoiceController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception

  before_action :load_installation
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from LightekReservations::Federation::Client::Unavailable,
    LightekCommunications::InstallationVoice::Unavailable, LightekCommunications::VoiceSetup::Invalid, with: :unavailable

  def show
    @voice = @installation.request("installation/voice/status")
  end

  def device
    @device = @installation.request("installation/voice/device")
  end

  def cellular_activation
    @cellular = @installation.request("installation/voice/cellular_activation")
  end

  def checkout
    setup = LightekCommunications::VoiceSetup
    fields = params.permit(:plan, number_request: %i[option area_code phone_number],
      voice_setup: [:confirm_emergency_address, :authorize_port, :document, { emergency: setup::ADDRESS_FIELDS, port: setup::PORT_FIELDS }]).to_h
    if (document = fields.dig("voice_setup", "document"))
      unless document.is_a?(ActionDispatch::Http::UploadedFile) && document.size.between?(1, 2.megabytes)
        raise setup::Invalid, "Upload your current carrier invoice as a PDF of up to 2 MB."
      end
      fields["voice_setup"]["document"] = Base64.strict_encode64(document.read(2.megabytes + 1))
    end
    result = @installation.request("installation/voice/checkout", fields)
    url = LightekCommunications::InstallationVoice.checkout_url!(result["checkout_url"])
    redirect_to url, allow_other_host: true, status: :see_other
  end

  private

  def load_installation
    response.headers["Cache-Control"] = "private, no-store"
    @installation = LightekTeam::Installation.new(current_user)
    raise LightekPeople::Access::Denied unless @installation.owner? &&
      !current_user.password_setup_required? && Current.session&.connect_delegation.blank?
  end

  def unavailable(error)
    if action_name == "show"
      flash.now[:alert] = error.message
      @voice = { "status" => "unavailable" }
      render :show, status: :service_unavailable
    else
      redirect_to dashboard_installation_voice_path, alert: error.message, status: :see_other
    end
  end
end
