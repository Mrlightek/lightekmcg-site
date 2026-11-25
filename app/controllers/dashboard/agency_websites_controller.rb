# frozen_string_literal: true

require "base64"

class Dashboard::AgencyWebsitesController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :set_site
  before_action :verify_editor!, only: %i[edit_site stage review deploy rollback]
  before_action :verify_release_access!, only: %i[stage review deploy rollback]

  rescue_from LightekAgency::WebsiteReleases::Invalid, LightekConnect::InstanceTransport::Unavailable,
    LightekAgency::PackagePolicy::Denied, ActiveRecord::RecordInvalid, ArgumentError, with: :failed
  rescue_from Gatekeeper::Hosting::Access::Denied, with: -> { head :forbidden }
  rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }

  def show
    @releases = []
    return unless @mfa_verified && @available

    @releases = if @peer
      rows = remote!("list", {}).fetch("releases")
      raise LightekConnect::InstanceTransport::Unavailable unless rows.is_a?(Array)

      rows
    else
      releases.list
    end
  rescue LightekConnect::InstanceTransport::Unavailable, KeyError
    @release_status_error = "The client application did not return its releases. Refresh to check its status."
  end

  def edit_site
    return redirect_to dashboard_website_designs_path(site_id: @site.id), status: :see_other unless @peer

    code = LightekConnect::AgencyDashboard.code!(actor: current_user, site: @site,
      destination: LightekConnect::AgencyDashboard::EDIT_DESTINATION)
    redirect_to "/connect/management?code=#{code}", status: :see_other
  end

  def stage
    upload = params.require(:theme_package)
    name = params.require(:name)
    key = params.require(:request_key)
    unless upload.respond_to?(:original_filename) && upload.original_filename.to_s.match?(/\.zip\z/i) &&
        upload.size.between?(1, LightekDesign::ThemePackage::MAX_ARCHIVE_BYTES)
      raise ArgumentError, "Choose a theme ZIP up to 6 MB."
    end
    unless name.is_a?(String) && name.strip.length.between?(1, 120) && key.to_s.match?(/\A[a-f0-9-]{36}\z/)
      raise ArgumentError, "Enter a valid theme name and reload the form if necessary."
    end

    if @peer
      bytes = upload.read(LightekDesign::ThemePackage::MAX_ARCHIVE_BYTES + 1)
      raise ArgumentError, "Choose a theme ZIP up to 6 MB." if bytes.bytesize > LightekDesign::ThemePackage::MAX_ARCHIVE_BYTES

      receipt = remote!("stage", {name: name, request_key: key, package_base64: Base64.strict_encode64(bytes)})["release"]
      unless receipt.is_a?(Hash) && receipt["name"] == name.strip && receipt["status"] == "draft"
        raise LightekConnect::InstanceTransport::Unavailable, "Client application did not confirm staging."
      end
    else
      releases.stage!(upload: upload, name: name, request_key: key)
    end
    redirect_to dashboard_agency_website_path(@site), notice: "Draft release staged on #{@site.host}.", status: :see_other
  end

  def deploy
    change_release!("deploy")
    redirect_to dashboard_agency_website_path(@site), notice: "Release deployed on #{@site.host}.", status: :see_other
  end

  def review
    change_release!("review")
    redirect_to dashboard_agency_website_path(@site), notice: "Current draft revision recorded for #{@site.host}.", status: :see_other
  end

  def rollback
    change_release!("rollback")
    redirect_to dashboard_agency_website_path(@site), notice: "Previous website theme restored on #{@site.host}.", status: :see_other
  end

  private

  def set_site
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Referrer-Policy"] = "same-origin"
    @site = LightekSettings::WebsiteIdentity.sites_for(current_user).find(params[:id])
    LightekConnect::AgencyDashboard.authorize!(current_user, @site)
    @peer = LightekReservations::Peer.find_by(site: @site)
    @available = @peer ? @peer.active? && @peer.merchant_id == @site.tenant_id : @site.manifest.to_h["network_ledger"] != true
    @mfa_verified = LightekConnect::MfaHandoff.source_verified?(Current.session, current_user)
  end

  def verify_editor!
    raise Gatekeeper::Hosting::Access::Denied, "This client application is unavailable." unless @available
  end

  def verify_release_access!
    raise Gatekeeper::Hosting::Access::Denied, "Verify your agency authenticator." unless @mfa_verified
  end

  def releases = LightekAgency::WebsiteReleases.new(site: @site, editor: current_user)

  def remote!(action, payload)
    LightekConnect::InstanceTransport.website_release!(peer: @peer, actor: current_user,
      session: Current.session, action: action, payload: payload)
  end

  def change_release!(action)
    id = Integer(params.require(:release_id).to_s, 10)
    revision = params.require(:revision)
    raise ArgumentError, "Reload this release before continuing." unless revision.to_s.match?(/\A[a-f0-9]{64}\z/)

    if @peer
      receipt = remote!(action, {id: id, revision: revision})["release"]
      status = {"deploy" => "deployed", "rollback" => "rolled_back", "review" => "draft"}.fetch(action)
      unless receipt.is_a?(Hash) && receipt["id"] == id && receipt["status"] == status &&
          (action == "review" || receipt["revision"] == revision)
        raise LightekConnect::InstanceTransport::Unavailable, "Client application did not confirm the release change."
      end
    else
      releases.public_send("#{action}!", id: id, revision: revision)
    end
  end

  def failed(error)
    return head :forbidden unless @site

    redirect_to dashboard_agency_website_path(@site), alert: error.message, status: :see_other
  end
end
