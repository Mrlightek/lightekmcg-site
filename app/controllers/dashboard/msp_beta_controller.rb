# frozen_string_literal: true

require "zip"
require "stringio"

class Dashboard::MspBetaController < ApplicationController
  skip_authorization_check
  protect_from_forgery with: :exception
  before_action :require_staging_session!
  layout "dymond_dash/layouts/dymond_dash"
  rate_limit to: 8, within: 1.minute, only: %i[enroll feedback revoke]
  rescue_from ItServices::BetaDevice::Denied, with: -> { head :forbidden }

  def show
    if @tester
      @device = ItServices::BetaDevice.find(current_user)
      @sessions = ItRemoteSupportSession.where(customer: current_user).order(id: :desc).limit(10)
    else
      assigned = ItServiceRequest.where(technician_id: current_user.id).select(:network_managed_device_id)
      @devices = NetworkManagedDevice.where(id: assigned).where("identifier LIKE ?", "msp-beta-%").order(id: :desc).limit(30)
    end
  end

  def download
    raise ItServices::BetaDevice::Denied unless @tester

    files = ItServices::BetaDevice::SUPPORT_FILES.map { |name| Rails.root.join("scripts", name) }
    return head :service_unavailable unless files.all?(&:file?)

    entry = Rails.root.join("deploy/it-support-staging/beta_check_in.py").read
    bundle = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("beta_check_in.py")
      zip.write(entry)
      files.each do |file|
        zip.put_next_entry(file.basename.to_s)
        zip.write(file.binread)
      end
    end
    send_data bundle.string, filename: "lightek-msp-beta.zip", type: "application/zip"
  end

  def enroll
    raise ItServices::BetaDevice::Denied unless @tester && params[:monitoring_consent] == "1"

    @device, @enrollment_token = ItServices::BetaDevice.issue!(current_user)
    @sessions = []
    render :show
  end

  def revoke
    raise ItServices::BetaDevice::Denied unless @tester

    ItServices::BetaDevice.revoke!(current_user)
    redirect_to dashboard_msp_beta_path, status: :see_other
  end

  def feedback
    raise ItServices::BetaDevice::Denied unless @tester && params[:synthetic_only] == "1"

    scenario = params[:scenario]
    result = params[:result]
    unless scenario.in?(%w[enrollment monitoring screen_sharing recording file_transfer input unattended maintenance]) &&
        result.in?(%w[passed failed blocked])
      return head :unprocessable_entity
    end

    return head :unprocessable_entity unless params[:beta_feedback].is_a?(String) && params[:beta_feedback].length.between?(1, 1000)

    ticket = NevaehCustomerService::Cases.open!(actor: current_user, topic: "technical",
      title: "MSP beta · #{scenario.humanize} · #{result}", description: params[:beta_feedback].to_s, record_id: nil)
    NevaehCustomerService::Cases.enqueue(ticket)
    redirect_to dashboard_customer_case_path(ticket), status: :see_other
  rescue NevaehCustomerService::Cases::Invalid
    redirect_to dashboard_msp_beta_path, alert: "Enter a short description using synthetic data.", status: :see_other
  end

  private

  def require_staging_session!
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
    return head :not_found unless ItServices::BetaDevice.staging_host?(request.host) && ItRemoteSupportSession.available? &&
      NetworkManagedDevice.column_names.include?("managed_monitoring_enabled")
    return head :forbidden unless Current.session && Current.session.connect_delegation.blank? && !Current.session.mfa_enrollment_only?

    @tester = ItServices::BetaDevice.tester?(current_user)
    return if @tester
    return if current_user.role.in?(%w[employee contractor admin super_admin]) && current_user.access_active? &&
      LightekIdentity::Mfa.enabled?(current_user) && LightekIdentity::Mfa.fresh?(Current.session)

    head :forbidden
  end
end
