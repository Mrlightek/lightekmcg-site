# frozen_string_literal: true

class LinearChannelStreamsController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session
  rescue_from LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, ActiveRecord::RecordNotFound, Errno::ENOENT do
    head :not_found
  end

  def show
    site = LightekPwa::SiteContext.resolve(request.host)
    channel = Studio::Broadcasting::Channel.where(site_id: site.id, managed_playout: true).find(params[:channel_id])
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
    if name == "index.m3u8"
      render plain: path.read, content_type: "application/vnd.apple.mpegurl"
    else
      send_file path, type: "video/mp2t", disposition: "inline"
    end
  end
end
