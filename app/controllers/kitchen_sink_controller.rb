# app/controllers/kitchen_sink_controller.rb

class KitchenSinkController < ApplicationController
    allow_unauthenticated_access
  API_VERSION = "1.0".freeze

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
        supported_screen_types: %w[
          home
          details
          search
          channel
          player
        ],
        supported_component_types: %w[
          hero
          navigation
          content_row
          poster_card
          landscape_card
          live_card
          text
        ],
        supported_action_types: %w[
          open_screen
          open_details
          play
          search
          exit
        ],
        supported_stream_formats: %w[
          hls
          mp4
        ]
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
            action: {
              type: "search"
            }
          }
        ]
      },
      hero: {
        component_type: "hero",
        id: "featured-hero",
        title: "Welcome to Lightek FAST",
        subtitle: "One network. Infinite distribution.",
        description: "Watch documentaries, music, activism, culture, and original programming.",
        background_image_url: "#{request.base_url}/images/roku/hero-background.jpg",
        logo_image_url: "#{request.base_url}/images/roku/lightek-fast-logo.png",
        actions: [
          {
            id: "hero-watch",
            label: "Watch Now",
            type: "play",
            content_id: "featured-stream",
            playback_url: "https://media.example.com/streams/featured/master.m3u8",
            stream_format: "hls"
          }
        ]
      },
      rows: [
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
              image_url: "#{request.base_url}/images/roku/featured-documentary.jpg",
              badge: "NEW",
              duration_seconds: 2700,
              action: {
                type: "open_details",
                target: "#{request.base_url}/roku/content/featured-001.json"
              }
            },
            {
              id: "featured-002",
              content_type: "live_channel",
              title: "Lightek Live",
              subtitle: "Streaming now",
              image_url: "#{request.base_url}/images/roku/lightek-live.jpg",
              badge: "LIVE",
              action: {
                type: "play",
                content_id: "featured-002",
                playback_url: "https://media.example.com/live/master.m3u8",
                stream_format: "hls"
              }
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
              image_url: "#{request.base_url}/images/roku/resistance-economy-poster.jpg",
              action: {
                type: "open_details",
                target: "#{request.base_url}/roku/content/documentary-001.json"
              }
            }
          ]
        }
      ],
      metadata: {
        generated_at: Time.current.iso8601,
        request_id: request.request_id
      }
    }
  end
end