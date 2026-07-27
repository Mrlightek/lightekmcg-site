# app/controllers/kitchen_sink_controller.rb

class KitchenSinkController < ApplicationController
  allow_unauthenticated_access

  API_VERSION = "1.0".freeze
  FEATURED_PLAYBACK_URL =
    "https://hls-harbor-livepush.akamaized.net/live_cdn/nsqIStpj8PaG-Ev/emcQJ0pGpremocy/index.m3u8".freeze
  LIVE_PLAYBACK_URL =
    "https://stream-akamai.castr.com/5b9352dbda7b8c769937e459/live_2361c920455111ea85db6911fe397b9e/index.fmp4.m3u8".freeze

  def platform_config
    render json: {
      schema_version: API_VERSION,
      platform: "roku",
      application: {
        id: "com.lightekmcg.fast",
        name: "Lightek FAST",
        environment: Rails.env,
        minimum_client_version: "1.0.0"
      },
      refresh: {
        configuration_ttl_seconds: 3600,
        screen_ttl_seconds: 300
      },
      endpoints: {
        home: kitchen_sink_url(format: :json)
      },
      theme: {
        colors: {
          background: "#080808",
          surface: "#151515",
          surface_focused: "#252525",
          primary: "#D4AF37",
          secondary: "#FFFFFF",
          text_primary: "#FFFFFF",
          text_secondary: "#B8B8B8",
          focus_border: "#D4AF37"
        },
        typography: {
          heading_font: "font:LargeBoldSystemFont",
          title_font: "font:MediumBoldSystemFont",
          body_font: "font:MediumSystemFont",
          caption_font: "font:SmallSystemFont"
        },
        dimensions: {
          screen_width: 1920,
          screen_height: 1080,
          safe_margin_horizontal: 90,
          safe_margin_vertical: 60,
          card_spacing: 24,
          row_spacing: 48
        }
      },
      capabilities: {
        supported_screen_types: %w[home details search channel player],
        supported_component_types: %w[
          hero navigation content_row poster_card landscape_card live_card text
        ],
        supported_action_types: %w[open_screen open_details play search exit],
        supported_stream_formats: %w[hls mp4]
      }
    }
  end

  def index
    render json: {
      schema_version: API_VERSION,
      screen: {
        id: "home",
        type: "home",
        title: "Lightek FAST",
        background_color: "#080808",
        refresh_after_seconds: 300,
        initial_focus: "featured-row"
      },
      navigation: {
        component_type: "navigation",
        items: [
          {
            id: "nav-home",
            label: "Home",
            selected: true,
            action: {
              type: "open_screen",
              target: kitchen_sink_url(format: :json)
            }
          },
          {
            id: "nav-live",
            label: "Live",
            action: {
              type: "open_screen",
              target: "#{request.base_url}/roku/screens/live.json"
            }
          },
          {
            id: "nav-search",
            label: "Search",
            action: { type: "search" }
          }
        ]
      },
      hero: {
        component_type: "hero",
        id: "featured-hero",
        title: "Welcome to Lightek FAST",
        subtitle: "One network. Infinite distribution.",
        description: "Watch documentaries, music, activism, culture, and original programming.",
        background_image_url: roku_image_url("hero-background.jpg"),
        logo_image_url: roku_image_url("lightek-fast-logo.png"),
        actions: [
          play_action(
            id: "hero-watch",
            label: "Watch Now",
            content_id: "featured-stream",
            playback_url: FEATURED_PLAYBACK_URL
          )
        ]
      },
      rows: home_rows,
      metadata: response_metadata
    }
  end

  def content
    payload =
      case params[:id]
      when "featured-001"
        featured_documentary_details
      when "documentary-001"
        resistance_economy_details
      else
        return render json: {
          schema_version: API_VERSION,
          error: {
            code: "content_not_found",
            message: "The requested Roku content does not exist."
          }
        }, status: :not_found
      end

    render json: payload.merge(metadata: response_metadata)
  end

  private

  def home_rows
    [
      {
        component_type: "content_row",
        id: "featured-row",
        title: "Featured",
        card_type: "landscape_card",
        card_width: 420,
        card_height: 236,
        items: [
          {
            id: "featured-001",
            content_type: "episode",
            title: "Featured Documentary",
            subtitle: "Lightek Originals",
            description: "The first featured program on the Lightek FAST network.",
            image_url: roku_image_url("featured-documentary.jpg"),
            hero_image_url: roku_image_url("featured-documentary.jpg"),
            badge: "NEW",
            duration_seconds: 2700,
            action: details_action("featured-001")
          },
          {
            id: "featured-002",
            content_type: "live_channel",
            title: "Lightek Live",
            subtitle: "Streaming now",
            image_url: roku_image_url("lightek-live.jpg"),
            hero_image_url: roku_image_url("lightek-live.jpg"),
            badge: "LIVE",
            indicator: {
              type: "status_dot",
              color: "#FF3B30"
            },
            action: play_action(
              id: "featured-live",
              label: "Watch Live",
              content_id: "featured-002",
              playback_url: LIVE_PLAYBACK_URL
            )
          }
        ]
      },
      {
        component_type: "content_row",
        id: "documentary-row",
        title: "Documentaries",
        card_type: "poster_card",
        card_width: 280,
        card_height: 420,
        items: [
          {
            id: "documentary-001",
            content_type: "show",
            title: "The Resistance Economy",
            subtitle: "Season 1",
            description: "A Lightek original documentary series about ownership, labor, and community power.",
            image_url: roku_image_url("resistance-economy-poster.jpg"),
            hero_image_url: roku_image_url("hero-background.jpg"),
            action: details_action("documentary-001")
          }
        ]
      }
    ]
  end

  def featured_documentary_details
    {
      schema_version: API_VERSION,
      screen: {
        id: "details-featured-001",
        type: "details",
        title: "Featured Documentary",
        background_color: "#080808"
      },
      details: {
        content_id: "featured-001",
        content_type: "documentary",
        title: "Featured Documentary",
        subtitle: "A Lightek Original",
        description: "Meet the people building durable institutions, independent media, and community-owned futures.",
        background_image_url: roku_image_url("featured-documentary.jpg"),
        badge: "NEW",
        metadata: {
          year: "2026",
          rating: "TV-14",
          duration: "45 min",
          genre: "Documentary"
        },
        actions: [
          play_action(
            id: "featured-001-watch",
            label: "Watch Now",
            content_id: "featured-001",
            playback_url: FEATURED_PLAYBACK_URL
          )
        ]
      },
      rows: [
        {
          component_type: "content_row",
          id: "featured-related",
          title: "More from Lightek",
          card_type: "landscape_card",
          card_width: 300,
          card_height: 169,
          items: [
            {
              id: "documentary-001",
              content_type: "show",
              title: "The Resistance Economy",
              subtitle: "Season 1",
              image_url: roku_image_url("resistance-economy-poster.jpg"),
              action: details_action("documentary-001")
            }
          ]
        }
      ]
    }
  end

  def resistance_economy_details
    {
      schema_version: API_VERSION,
      screen: {
        id: "details-documentary-001",
        type: "details",
        title: "The Resistance Economy",
        background_color: "#080808"
      },
      details: {
        content_id: "documentary-001",
        content_type: "documentary series",
        title: "The Resistance Economy",
        subtitle: "Season 1",
        description: "A documentary series following builders creating community ownership, resilient local economies, and independent cultural power.",
        background_image_url: roku_image_url("hero-background.jpg"),
        metadata: {
          year: "2026",
          rating: "TV-14",
          duration: "1 Season",
          genre: "Documentary"
        },
        actions: [
          play_action(
            id: "documentary-001-watch",
            label: "Watch Episode 1",
            content_id: "documentary-001-episode-001",
            playback_url: FEATURED_PLAYBACK_URL
          )
        ]
      },
      rows: [
        {
          component_type: "content_row",
          id: "documentary-001-episodes",
          title: "Episodes",
          card_type: "landscape_card",
          card_width: 300,
          card_height: 169,
          items: [
            {
              id: "documentary-001-episode-001",
              content_type: "episode",
              title: "Episode 1",
              subtitle: "The Work Begins",
              description: "The builders define what ownership means and begin laying the foundation.",
              image_url: roku_image_url("featured-documentary.jpg"),
              badge: "NEW",
              action: play_action(
                id: "episode-001-play",
                label: "Play",
                content_id: "documentary-001-episode-001",
                playback_url: FEATURED_PLAYBACK_URL
              )
            }
          ]
        }
      ]
    }
  end

  def details_action(content_id)
    {
      type: "open_details",
      target: roku_content_url(id: content_id, format: :json)
    }
  end

  def play_action(id:, label:, content_id:, playback_url:)
    {
      id: id,
      label: label,
      type: "play",
      content_id: content_id,
      playback_url: playback_url,
      stream_format: "hls"
    }
  end

  def roku_image_url(filename)
    "#{request.base_url}/images/roku/#{filename}"
  end

  def response_metadata
    {
      generated_at: Time.current.iso8601,
      request_id: request.request_id
    }
  end
end
