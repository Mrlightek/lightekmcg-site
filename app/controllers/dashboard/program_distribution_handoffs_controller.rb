# frozen_string_literal: true

class Dashboard::ProgramDistributionHandoffsController < Dashboard::SettingsHomeController
  include ActionController::Live
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :load_site

  rescue_from ArgumentError, ActiveRecord::RecordInvalid, Studio::Broadcasting::HostedPrograms::Unavailable,
    LightekReservations::Federation::Client::Unavailable do |error|
    redirect_to dashboard_broadcast_network_path(site_id: @site.id), alert: error.message, status: :see_other
  end
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end

  def create
    license = licenses.find(params[:license_id])
    fields = params.require(:handoff).permit(:platform, :partner, :territories, :starts_at, :ends_at, :commercial)
    Studio::Broadcasting::ProgramDistributionHandoff.create!(license: license, operator: current_user,
      platform: fields[:platform], partner: fields[:partner].to_s.strip, territories: fields[:territories],
      starts_at: Time.zone.parse(fields[:starts_at].to_s), ends_at: Time.zone.parse(fields[:ends_at].to_s), commercial: fields[:commercial] == "1")
    redirect_to dashboard_broadcast_network_path(site_id: @site.id), notice: "Partner handoff prepared for review.", status: :see_other
  end

  def show
    @handoff = find_handoff
    @handoff.authorize_delivery!
  end

  def review
    handoff = find_handoff
    fields = params.require(:handoff).permit(:spec_reference, checks: Studio::Broadcasting::ProgramDistributionHandoff::REVIEW_CHECKS.keys)
    handoff.record_review!(reference: fields[:spec_reference], checks: fields.fetch(:checks, {}))
    redirect_to dashboard_program_distribution_package_path(handoff, site_id: @site.id),
      notice: "Partner specification review recorded.", status: :see_other
  end

  def record_submission
    handoff = find_handoff
    handoff.record_submission!(reference: params[:submission_reference])
    redirect_to dashboard_program_distribution_package_path(handoff, site_id: @site.id),
      notice: "Partner submission receipt recorded.", status: :see_other
  end

  def manifest
    handoff = find_handoff
    send_data JSON.pretty_generate(handoff.manifest), filename: "program-handoff-#{handoff.id}.json", type: "application/json"
  end

  def media
    handoff = find_handoff
    handoff.authorize_delivery!
    if params[:format] == "master"
      blob = handoff.master
      raise ActiveRecord::RecordNotFound unless blob
    else
      blob = handoff.license.asset.proxy.blob
    end

    send_stream(filename: "licensed-program-#{handoff.id}#{blob.filename.extension_with_delimiter}", type: blob.content_type) do |stream|
      blob.download { |chunk| stream.write(chunk) }
    end
  end

  private

  def load_site
    response.set_header("Cache-Control", "private, no-store")
    access = Studio::Broadcasting::Access
    @site = access.site(user: current_user, host: request.host, id: params[:site_id])
    raise ActiveRecord::RecordNotFound unless @site

    access.authorize!(current_user, @site)
    raise LightekPwa::Policy::Denied, "A site administrator must manage partner handoffs." unless
      LightekPwa::Policy.new(user: current_user, site: @site).role == "admin"
  end

  def licenses = Studio::Broadcasting::ProgramLicense.where(licensee_site: @site)

  def find_handoff
    Studio::Broadcasting::ProgramDistributionHandoff.where(license_id: licenses.select(:id)).find(params[:id])
  end
end
