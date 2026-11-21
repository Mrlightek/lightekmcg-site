# frozen_string_literal: true

class BroadcastTvController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session

  def show
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "same-origin")
    site = LightekPwa::SiteContext.resolve(request.host)
    experience = Studio::Broadcasting::Experience.new(site: site, user: current_user, platform: "web",
      slug: params[:application].presence, origin: request.base_url)
    if Studio::Advertising::StreamProfile.where(site: site).exists?
      offer = Studio::Advertising::ViewingOffer.find_by(site: site)
      @viewing_product = offer.product if offer&.valid?
      @fewer_commercials = Studio::Advertising::ViewingOffer.active?(site, current_user) if @viewing_product
    end
    @guide = experience.home(live: true)
    @channels = @guide[:rows].find { |row| row[:id] == "live-channels" }&.fetch(:items) || []
    @schedule = @guide[:rows].find { |row| row[:id] == "program-guide" }&.fetch(:items) || []
    @selected = @channels.find { |channel| channel[:id] == params[:channel] }
    if @selected&.dig(:action, :measurement_url)
      @nielsen = Studio::Broadcasting::Nielsen.browser_configuration(site)
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def measurement
    response.set_header("Cache-Control", "private, no-store")
    site = LightekPwa::SiteContext.resolve(request.host)
    LightekPwa::Policy.new(user: current_user, site: site).authorize!("watch")
    channel = Studio::Broadcasting::Channel.find_by(site: site, id: params[:channel_id], managed_playout: true, status: "published")
    channel ||= Studio::Broadcasting::NetworkCarriage.find_visible(site, params[:channel_id], user: current_user)
    token = Studio::Broadcasting::Audience.identity(params[:view_session], channel: channel, outlet: site)
    return head :not_found unless token

    render json: { timeline: Studio::Broadcasting::Nielsen.timeline(channel, distributor: channel.site_id != site.id) }
  rescue ActiveRecord::RecordNotFound, LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied
    head :not_found
  end
end
