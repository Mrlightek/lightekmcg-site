# frozen_string_literal: true

class Dashboard::InstallationVoiceController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception

  before_action :load_installation
  rescue_from LightekPeople::Access::Denied, with: -> { head :forbidden }
  rescue_from LightekReservations::Federation::Client::Unavailable,
    LightekCommunications::InstallationVoice::Unavailable, with: :unavailable

  def show
    @voice = @installation.request("installation/voice/status")
  end

  def checkout
    fields = params.permit(:plan, number_request: %i[option area_code phone_number])
    result = @installation.request("installation/voice/checkout", fields.to_h)
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
