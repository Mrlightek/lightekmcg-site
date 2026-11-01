# frozen_string_literal: true
require "uri"
module Studio
  module Broadcasting
    # The existing Roku contract now reads persisted application controls and the
    # same audience-authorized media store used by Studio and the PWA.
    class Experience
      attr_reader :site, :application, :access
      def initialize(site:, user:, platform:, slug: nil, origin:)
        @site, @origin = site, origin
        raise ArgumentError, "Unsupported OTT platform" unless Application::PLATFORMS.include?(platform)
        apps = Application.where(site_id: site.id, platform: platform)
        @application = slug.present? ? apps.find_by!(slug: slug) : apps.order(:id).first
        @application ||= Application.new(site: site, name: site.name, slug: "default", platform: platform)
        @access = LightekCommunity::Access.new(user: user, site_id: site.id)
        @config = @application.configuration
        @available = @application.status == "published"
        begin
          LightekPwa::Policy.new(user: user, site: site).authorize!("watch")
        rescue LightekPwa::Policy::Denied
          @available = false
        end
      end
      def url(path, extra = {})
        query = {platform: application.platform}.merge(application.persisted? ? {application: application.slug} : {}).merge(extra)
        "#{@origin}#{path}?#{URI.encode_www_form(query)}"
      end
      def config
        {schema_version: "1.0", platform: application.platform.upcase, application: {
          id: "com.lightekmcg.#{site.id}.#{application.slug}", name: application.name,
          environment: Rails.env, status: @available ? "published" : "maintenance", minimum_client_version: application.minimum_client_version,
          revision: revision}, refresh: {configuration_ttl_seconds: @config["configuration_ttl"], screen_ttl_seconds: @config["configuration_ttl"]},
          endpoints: {home: url("/gatekeeper"), live: url("/gatekeeper/screens/live"), search: url("/gatekeeper/search")},
          theme: {colors: {background: @config["background"], primary: @config["accent"], focus_border: @config["accent"], text_primary: "#FFFFFF", text_secondary: "#B8B8B8", surface: "#151515", surface_focused: "#252525"},
            typography: {heading_font: "font:LargeBoldSystemFont", title_font: "font:MediumBoldSystemFont", body_font: "font:MediumSystemFont", caption_font: "font:SmallSystemFont"},
            dimensions: {screen_width: 1920, screen_height: 1080, safe_margin_horizontal: 90, safe_margin_vertical: 60, card_spacing: 24, row_spacing: 48}},
          controls: @config.slice("autoplay", "captions", "search", "live", "catalog"),
          capabilities: {supported_screen_types: %w[home details search channel player], supported_component_types: %w[hero navigation content_row poster_card landscape_card live_card text], supported_action_types: %w[open_screen open_details play search exit], supported_stream_formats: %w[hls mp4]}}
      end
      def posts
        base = access.posts.where(parent_id: nil, distribution: %w[lightek_streaming octavia], kind: %w[video live])
        # Moderation applies even to a super-admin preview of a published outlet.
        return base.none unless @available
        kinds = []
        kinds << "video" if @config["catalog"]
        kinds << "live" if @config["live"]
        base = base.where(id: @config["post_ids"]) if @config["catalog_source"] == "selected"
        base.where(kind: kinds, moderation_state: "published").order(id: :desc)
      end
      def home(query: nil, live: false)
        records = posts
        records = records.where("LOWER(title) LIKE ?", "%#{Post.sanitize_sql_like(query.to_s.downcase.first(100))}%") if query.present? && @config["search"]
        records = records.none if query.present? && !@config["search"]
        records = records.where(kind: "live") if live
        records = records.where.not(kind: "live") unless @config["live"]
        items = records.includes(media_attachments: :blob).limit(100).filter_map { |post| card(post) }
        rows = []
        if @available && @config["live"] && (live || query.blank?)
          channels = active_channels
          channel_items = channels.map { |channel| channel_card(channel) }
          rows << row("live-channels", "Live channels", channel_items) if channel_items.any?
        end
        rows << row("published-media", live ? "Live broadcasts" : "Latest releases", items) if items.any?
        rows << schedule_row if @available && @config["live"] && query.blank?
        rows.compact!
        hero = rows.flat_map { |entry| entry[:items] }.first
        {schema_version: "1.0", screen: {id: live ? "live" : "home", type: live ? "channel" : "home", title: application.name,
          background_color: @config["background"], refresh_after_seconds: @config["configuration_ttl"], initial_focus: rows.first&.dig(:id)},
          navigation: {component_type: "navigation", items: navigation},
          hero: hero && {component_type: "hero", id: "featured", title: hero[:title], subtitle: @config["welcome_message"], background_image_url: hero[:image_url], actions: [hero[:action]]},
          rows: rows, metadata: {revision: revision, application_status: @available ? "published" : "maintenance", empty_message: @available ? "No published programming yet." : "This application is off air."}}
      end
      def content(id)
        post = posts.find(id)
        item = card(post)
        raise ActiveRecord::RecordNotFound unless item
        {schema_version: "1.0", screen: {id: "content-#{post.id}", type: "details", title: post.title},
          details: item.merge(actions: [play_action(post)]), rows: [], metadata: {revision: revision}}
      end
      private
      def revision = "#{application.lock_version}-#{application.updated_at&.to_i}"
      def navigation
        items = [{id: "nav-home", label: "Home", action: {type: "open_screen", target: url("/gatekeeper")}}]
        items << {id: "nav-watch", label: "Live TV", action: {type: "open_screen", target: url("/gatekeeper/screens/live")}} if @config["live"]
        items << {id: "nav-search", label: "Search", action: {type: "search", target: url("/gatekeeper/search")}} if @config["search"]
        items
      end
      def row(id, title, items)
        {component_type: "content_row", id: id, title: title, card_type: "landscape_card", card_width: 420, card_height: 236, items: items}
      end
      def card(post)
        action = play_action(post)
        return unless action
        image = post.media.find { |file| file.blob.content_type.start_with?("image/") }
        {id: post.id.to_s, content_id: post.id.to_s, content_type: post.kind, title: post.title,
          description: post.content, is_live: post.kind == "live", image_url: image && "#{@origin}/api/lightek/pwa/posts/#{post.id}/media/#{image.id}",
          action: {type: "open_details", target: url("/gatekeeper/content/#{post.id}")}}
      end
      def play_action(post)
        if post.kind == "live"
          return unless @config["live"]
          operation = StudioLiveOperation.find_by(id: post.metadata["live_operation_id"], status: "live")
          return unless operation && operation.studio_project.site_id == site.id
          playback = "#{@origin}/api/lightek/pwa/live/#{post.id}/index.m3u8"
          format = "hls"
        else
          file = post.media.find { |attachment| attachment.blob.content_type == "video/mp4" }
          return unless file
          playback = "#{@origin}/api/lightek/pwa/posts/#{post.id}/media/#{file.id}"
          format = "mp4"
        end
        {type: "play", id: "play-#{post.id}", label: "Watch", content_id: post.id.to_s, playback_url: playback, stream_format: format,
          autoplay: @config["autoplay"], captions: @config["captions"]}
      end
      def channel_card(channel)
        {id: "channel-#{channel.id}", title: channel.name, description: channel.description, image_url: channel.image_url, is_live: true, badge: "LIVE",
          action: {type: "play", id: "play-channel-#{channel.id}", label: "Watch live", content_id: "channel-#{channel.id}", playback_url: channel.playback_url,
            stream_format: URI.parse(channel.playback_url).path.end_with?(".m3u8") ? "hls" : "mp4", captions: @config["captions"], autoplay: @config["autoplay"]}}
      end
      def active_channels
        scope = Channel.where(site_id: site.id, status: "published").order(:position, :id)
        @config["channel_source"] == "selected" ? scope.where(id: @config["channel_ids"]) : scope
      end
      def schedule_row
        slots = Program.where(channel_id: active_channels.select(:id)).where("ends_at > ?", Time.current)
          .where(post_id: posts.select(:id)).includes(:post).order(:starts_at).limit(50)
        items = slots.filter_map do |slot|
          item = card(slot.post)
          item&.merge(starts_at: slot.starts_at.iso8601, ends_at: slot.ends_at.iso8601, subtitle: slot.starts_at <= Time.current ? "On now" : "Up next")
        end
        row("program-guide", "On now & up next", items) if items.any?
      end
    end
  end
end
