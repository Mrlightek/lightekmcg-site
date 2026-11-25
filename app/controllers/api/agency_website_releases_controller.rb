# frozen_string_literal: true

require "base64"

class Api::AgencyWebsiteReleasesController < ActionController::Base
  skip_forgery_protection
  before_action :verify_instance!, :verify_agency_release!

  rescue_from LightekAgency::WebsiteReleases::Invalid, LightekAgency::PackagePolicy::Denied,
    ActiveRecord::RecordInvalid, ArgumentError, ActionController::ParameterMissing, with: :invalid
  rescue_from ActiveRecord::RecordNotFound, KeyError, Gatekeeper::Hosting::Access::Denied,
    LightekVault::Service::AccessDenied, with: -> { head :forbidden }
  rescue_from LightekReservations::Federation::Client::Unavailable, with: -> { head :service_unavailable }

  def index
    render json: {host: @site.host, releases: releases.list}
  end

  def stage
    value = params.require(:package_base64)
    limit = LightekDesign::ThemePackage::MAX_ARCHIVE_BYTES
    raise ArgumentError, "Choose a theme ZIP up to 6 MB." unless value.is_a?(String) && value.bytesize <= 4 * ((limit + 2) / 3)

    upload = LightekDesign::ThemePackage::Upload.new(Base64.strict_decode64(value), "theme.zip")
    release = releases.stage!(upload: upload, name: params.require(:name), request_key: params.require(:request_key))
    render json: {host: @site.host, release: release}
  end

  def deploy
    render json: {host: @site.host, release: releases.deploy!(id: params.require(:id), revision: params.require(:revision))}
  end

  def review
    render json: {host: @site.host, release: releases.review!(id: params.require(:id), revision: params.require(:revision))}
  end

  def rollback
    render json: {host: @site.host, release: releases.rollback!(id: params.require(:id), revision: params.require(:revision))}
  end

  private

  def releases = LightekAgency::WebsiteReleases.new(site: @site, editor: @owner, actor: @agency_actor)

  def verify_instance!
    response.headers["Cache-Control"] = "no-store"
    return head :upgrade_required if Rails.env.production? && !request.ssl?

    @site = DymondSite::Site.find_by!(host: request.host)
    @owner = @site.tenant
    # Use configuration belonging to this hostname, never the installation fallback.
    @config = @site.manifest.to_h["lightek_reservation_federation"]
    unless @config && @owner.is_a?(User) && @owner.role.in?(%w[client white_label]) &&
        LightekPeople::LifecycleAccess.active?(@owner) && LightekConnect::MfaHandoff.allowed_for?(@owner)
      return head :forbidden
    end

    secret = LightekVault::Service.checkout!(slug: @config.fetch("credential_slug"), consumer: LightekReservations::Federation::Client::CONSUMER,
      purpose: "reservation_federation", requested_by: "agency-website-release")
    token = request.authorization.to_s.delete_prefix("Bearer ")
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(secret.fetch("token"), token)
  ensure
    secret&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? }
  end

  def verify_agency_release!
    code = request.headers["X-Lightek-Release-Code"]
    return head :forbidden unless code.to_s.match?(/\A[0-9a-f]{64}\z/)

    operation = action_name == "index" ? "list" : action_name
    data = LightekReservations::Federation::Client.new(@site).request("connect/redeem", method: :post, body: {code: code, release_action: operation})
    unless @owner.email_address == data.fetch("owner_email") && data["agency_release_action"] == operation
      raise Gatekeeper::Hosting::Access::Denied
    end
    proof = data.fetch("delegation")
    LightekConnect::MfaHandoff.validate_context!(proof, connection_id: proof.fetch("connection_id"), grant_id: proof.fetch("grant_id"))
    @agency_actor = proof.fetch("actor")
    LightekAgency::PackagePolicy.authorize!(@owner, "design")
  end

  def invalid(error)
    render json: {host: @site&.host, error: error.message.to_s.first(220)}, status: :unprocessable_entity
  end
end
