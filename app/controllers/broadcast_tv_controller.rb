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
    @guide = experience.home(live: true)
    @channels = @guide[:rows].find { |row| row[:id] == "live-channels" }&.fetch(:items) || []
    @schedule = @guide[:rows].find { |row| row[:id] == "program-guide" }&.fetch(:items) || []
    @selected = @channels.find { |channel| channel[:id] == params[:channel] }
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end
end
