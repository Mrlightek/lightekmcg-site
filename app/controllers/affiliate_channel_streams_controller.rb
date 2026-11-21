# frozen_string_literal: true

class AffiliateChannelStreamsController < ApplicationController
  allow_unauthenticated_access
  before_action :resume_session, only: :show
  before_action { response.set_header("Cache-Control", "private, no-store") }
  rescue_from ActiveRecord::RecordNotFound, LightekPwa::Policy::Denied, LightekAgency::PackagePolicy::Denied, Errno::ENOENT do
    head :not_found
  end
  rescue_from Studio::Broadcasting::InstallationCarriage::Unavailable do |error|
    if @relay_entry && params[:name] == "index.m3u8" && !request.head? &&
        !error.is_a?(Studio::Broadcasting::InstallationCarriage::Rejected)
      Studio::Broadcasting::BroadcastFeedIncident.observe!(@relay_entry, "unavailable")
    end
    head :service_unavailable
  end

  def show
    site = LightekPwa::SiteContext.resolve(request.host)
    raise ActiveRecord::RecordNotFound unless Studio::Broadcasting::NetworkCarriage.hub?(site)
    LightekPwa::Policy.new(user: current_user, site: site).authorize!("watch")
    entry = Studio::Broadcasting::HostedCarriage.available.find_by!(key: params[:key])
    raise ActiveRecord::RecordNotFound unless entry.peer.active?
    @relay_entry = entry
    audience = Studio::Broadcasting::Audience
    token = params[:view_session]
    viewer = audience.identity(token, channel: entry, outlet: site)
    name = params.fetch(:name)
    raise ActiveRecord::RecordNotFound if name == "measurement.json" && !viewer

    relay_viewer = request.head? ? nil : viewer
    bytes, type, metadata = if entry.fallback_channel_id? || entry.relay_cursor.present?
      Studio::Broadcasting::AffiliateFailover.new(entry, outlet: site, viewer: relay_viewer).fetch(name)
    else
      raise ActiveRecord::RecordNotFound if name.start_with?("fallback-")

      Studio::Broadcasting::InstallationCarriage.relay!(entry, name, viewer: relay_viewer)
    end
    if name == "index.m3u8"
      # Relay accepts only the station's own HLS segment filenames.
      bytes = validated_playlist(bytes)
      if entry.observed_feed_state == "unavailable" && !entry.fallback_channel_id? && entry.relay_cursor.blank? && !request.head?
        Studio::Broadcasting::BroadcastFeedIncident.observe!(entry, "station")
      end
      bytes = audience.instrument_playlist(bytes, token) if viewer
    elsif name.end_with?(".ts") && viewer && metadata && !request.head?
      record_hub_view(audience, viewer, site, entry, name, metadata)
    end
    render body: bytes, content_type: type
  end

  def source
    return head :upgrade_required if Rails.env.production? && !request.ssl?

    entry = Studio::Broadcasting::NetworkCarriage.find_by!(remote_key: params[:key])
    channel = entry.channel
    raise ActiveRecord::RecordNotFound unless request.host == channel.site.host
    Studio::Broadcasting::InstallationCarriage.authorize_edge!(entry, request.authorization)
    name = params.fetch(:name)
    if name == "measurement.json"
      render json: { timeline: Studio::Broadcasting::Nielsen.timeline(channel, distributor: true) }
      return
    end
    file = Studio::Broadcasting::PlayoutMedia.channel_path(channel.id).join(name)
    return head :service_unavailable if name == "index.m3u8" && !file.file?
    raise ActiveRecord::RecordNotFound unless file.file?

    if name == "index.m3u8"
      render plain: file.read, content_type: "application/vnd.apple.mpegurl"
    else
      record_edge_view(channel, file)
      send_file file, type: "video/mp2t", disposition: "inline"
    end
  end

  private

  def validated_playlist(bytes)
    lines = bytes.lines
    unless lines.all? { |line| line.strip.empty? || line.start_with?("#") || line.strip.match?(/\A(?:fallback-\d+-)?out-\d+\.ts\z/) } &&
        lines.grep(/\A#/).none? { |line| line.match?(/\bURI=/i) }
      raise Studio::Broadcasting::InstallationCarriage::Unavailable, "The station returned an unsupported playlist."
    end

    bytes
  end

  def record_hub_view(audience, viewer, site, entry, name, metadata)
    audience.record_metadata(claims: viewer, outlet: site, channel: entry, sequence: name[/\d+/].to_i, metadata: JSON.parse(metadata))
  rescue JSON::ParserError
    nil
  end

  def record_edge_view(channel, file)
    id = request.headers["X-Lightek-Playback"]
    platform = request.headers["X-Lightek-Platform"]
    return unless id.to_s.match?(/\A[0-9a-f-]{36}\z/) && Studio::Broadcasting::Application::PLATFORMS.include?(platform)
    segment = Studio::Broadcasting::Nielsen.read_segment(file.sub_ext(".json"))
    return unless segment

    metadata = segment.slice("airing_id", "aired_at", "ad_row", "media_ms")
    response.set_header("X-Lightek-Media", JSON.generate(metadata))
    Studio::Broadcasting::Audience.record_metadata(claims: { "id" => id, "platform" => platform }, outlet: channel.site,
      channel: channel, sequence: file.basename.to_s[/\d+/].to_i, metadata: metadata)
  end
end
