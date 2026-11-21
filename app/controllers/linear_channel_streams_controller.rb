# frozen_string_literal: true

class LinearChannelStreamsController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, ActiveRecord::RecordNotFound, Errno::ENOENT do
    head :not_found
  end

  def show
    site = LightekPwa::SiteContext.resolve(request.host)
    channels = Studio::Broadcasting::Channel.where(managed_playout: true)
    channel = channels.find_by(site_id: site.id, id: params[:channel_id])
    channel ||= Studio::Broadcasting::NetworkCarriage.find_visible(site, params[:channel_id], user: current_user)
    if channel.status == "published"
      LightekPwa::Policy.new(user: current_user, site: site).authorize!("watch")
    elsif channel.status == "draft"
      Studio::Broadcasting::Access.authorize!(current_user, site)
    else
      raise ActiveRecord::RecordNotFound
    end
    response.set_header("Cache-Control", "private, no-store")
    name = params[:name].to_s
    raise ActiveRecord::RecordNotFound unless name == "index.m3u8" || /\Aout-\d+\.ts\z/.match?(name)
    path = Studio::Broadcasting::PlayoutMedia.channel_path(channel.id).join(name)
    raise ActiveRecord::RecordNotFound unless path.file?
    token = params[:view_session]
    identity = Studio::Broadcasting::Audience.identity(token, channel: channel, outlet: site) if channel.status == "published"
    if name == "index.m3u8"
      playlist = path.read
      playlist = Studio::Broadcasting::Audience.instrument_playlist(playlist, token) if identity
      render plain: playlist, content_type: "application/vnd.apple.mpegurl"
    else
      if identity && !request.head?
        Studio::Broadcasting::Audience.record(claims: identity, outlet: site, channel: channel, path: path)
      end
      unless request.head?
        Studio::Broadcasting::DeliveryUsage.observe(site_id: site.id, channel_key: channel.id, metric: :bytes_served, amount: path.size)
      end
      send_file path, type: "video/mp2t", disposition: "inline"
    end
  end
end
