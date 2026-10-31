# app/controllers/gatekeeper_controller.rb

class GatekeeperController < ApplicationController
  allow_unauthenticated_access

  API_VERSION = "1.0".freeze
  LIGHTEK_ENV = Rails.env
  LIGHTEK_NETWORK_LISTENER = :listener
  LIGHTEK_SERVER = :server
  LIGHTEK_PLATFORM_ID = "com.lightekmcg.fast"
  LIGHTEK_PLATFORM_NAME = "Octavia"
  LIGHTEK_PLATFORM_DEVICE = "ROKU"
  LIGHTEK_MINIMUM_CLIENT_VERSION = "1.0.0"
  LIGHTEK_CONFIGURATION_TTL_SECONDS = 3600
  LIGHTEK_SCREEN_TTL_SECONDS = 300
  LIGHTEK_THEME_COLORS = :lightek_theme_colors
  LIGHTEK_SUPPORTED_SCREEN_TYPES = :supported_screen_types
  LIGHTEK_SUPPORTED_COMPONENT_TYPES = :supported_component_types
  LIGHTEK_SUPPORTED_ACTION_TYPES = :supported_action_types
  LIGHTEK_SUPPORTED_STREAM_FORMATS = :supported_stream_formats
  LIGHTEK_THEME_TYPOGRAPHY =  :theme_typography
  LIGHTEK_THEME_DIMENSIONS = :theme_dimensions
  LIGHTEK_ALLOWED_ACTIONS = :permitted_actions
  LIGHTEK_REQUEST_ERROR = :request_error_message
  FEATURED_PLAYBACK_URL =
    "https://hls-harbor-livepush.akamaized.net/live_cdn/nsqIStpj8PaG-Ev/emcQJ0pGpremocy/index.m3u8".freeze
  LIVE_PLAYBACK_URL =
    "https://stream-akamai.castr.com/5b9352dbda7b8c769937e459/live_2361c920455111ea85db6911fe397b9e/index.fmp4.m3u8".freeze

  # Explicit Gatekeeper device API dispatcher. Never dynamically dispatch arbitrary
  # controller methods supplied by the client.
  def device_api
    action = params[:method_type].to_s
    unless permitted_actions.include?(action)
      return render json: { error: "Action not permitted" }, status: :bad_request
    end

    device = NetworkManagedDevice.find_by(identifier: params[:identifier].to_s)
    return render json: { error: "Device not registered" }, status: :unauthorized unless device
    return render json: { error: "Device retired" }, status: :forbidden if device.status == "retired"

    token = request.authorization.to_s.delete_prefix("Bearer ").strip
    unless request.authorization.to_s.start_with?("Bearer ") && device.authenticate_enrollment_token?(token)
      return render json: { error: "Invalid device credentials" }, status: :unauthorized
    end

    case action
    when "device_enroll"
      return render json: { error: "Device is suspended" }, status: :forbidden if device.status == "maintenance"
      device.update!(enrolled_at: Time.current, last_seen_at: Time.current,
        last_heartbeat_ip: request.remote_ip, status: "active")
      render json: { ok: true, device_id: device.id, status: device.status }
    when "device_heartbeat"
      return render json: { error: "Enrollment required" }, status: :forbidden unless device.enrolled_at?
      return render json: { error: "Device is not active" }, status: :forbidden unless %w[active offline].include?(device.status)
      device.update!(last_seen_at: Time.current, last_heartbeat_ip: request.remote_ip,
        status: "active")
      render json: { ok: true, device_id: device.id, status: device.status,
        server_time: Time.current.iso8601 }
    end
  end

  # Legacy Octavia dispatcher: allowlist is evaluated as data, never as a
  # method name or dynamic controller target.
  def octavia
    action = params[:method_type].to_s
    return render json: request_error_message, status: :bad_request unless permitted_actions.include?(action)
    return render json: { error: "Use the device API endpoint" }, status: :bad_request if action.start_with?("device_")
    render json: { error: "Unsupported action" }, status: :bad_request
  end

  def init_cloud_instance
    #connect to cloud instance
    #conduct business
    #leave
    end
    
    def request_error_message
    { error: "Invalid or unauthorized method type" }
    end
    
    def permitted_actions
    %w[device_enroll device_heartbeat]
    end
    
    def lightek_theme_colors
    {
          background: "#080808",
          surface: "#151515",
          surface_focused: "#252525",
          primary: "#D4AF37",
          secondary: "#FFFFFF",
          text_primary: "#FFFFFF",
          text_secondary: "#B8B8B8",
          focus_border: "#D4AF37"
        }
      end

  def theme_dimensions
     {
          screen_width: 1920,
          screen_height: 1080,
          safe_margin_horizontal: 90,
          safe_margin_vertical: 60,
          card_spacing: 24,
          row_spacing: 48
        }
        end
        
        def theme_typography
      {
          heading_font: "font:LargeBoldSystemFont",
          title_font: "font:MediumBoldSystemFont",
          body_font: "font:MediumSystemFont",
          caption_font: "font:SmallSystemFont"
        }
        end

  def fetch_users
    { users: User.all.as_json(only: [:id, :name]) }
  end

  def fetch_inventory
    { items: Current.user.inventory_items }
  end

  def update_settings
    # Do work using params...
    { success: true, message: "Settings updated for #{Current.user.name}" }
  end
    
    def platform_config
    render json: {
      schema_version: API_VERSION,
      platform: LIGHTEK_PLATFORM_DEVICE,
      application: {
        id: LIGHTEK_PLATFORM_ID,
        name: LIGHTEK_PLATFORM_NAME,
        environment: LIGHTEK_ENV,
        minimum_client_version: LIGHTEK_MINIMUM_CLIENT_VERSION
      },
      refresh: {
        configuration_ttl_seconds: LIGHTEK_CONFIGURATION_TTL_SECONDS,
        screen_ttl_seconds: LIGHTEK_SCREEN_TTL_SECONDS
      },
      endpoints: {
        home: gatekeeper_url(format: :json)
      },
      theme: {
        colors: LIGHTEK_THEME_COLORS,
        typography: LIGHTEK_THEME_TYPOGRAPHY,
        dimensions: LIGHTEK_THEME_DIMENSIONS
      },
      capabilities: {
        supported_screen_types: LIGHTEK_SUPPORTED_SCREEN_TYPES,
        supported_component_types: LIGHTEK_SUPPORTED_COMPONENT_TYPES,
        supported_action_types: LIGHTEK_SUPPORTED_ACTION_TYPES,
        supported_stream_formats: LIGHTEK_SUPPORTED_STREAM_FORMATS
      }
    }
  end

   
  def supported_stream_formats
    %w[hls mp4]
    end
    
    def supported_action_types
    %w[open_screen open_details play search exit]
    end
    
    def supported_screen_types 
    %w[home details search channel player]
  end

  def supported_component_types
    %w[hero navigation content_row poster_card landscape_card live_card text]
  end

def index
  render json: {
    schema_version: API_VERSION,
    screen: {
      id: "home",
      type: "home",
      title: "Lightek",
      background_color: "#080808",
      refresh_after_seconds: 300,
      initial_focus: "people-you-follow"
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
            target: gatekeeper_url(format: :json)
          }
        },
        {
          id: "nav-watch",
          label: "Watch",
          action: {
            type: "open_screen",
            target: gatekeeper_live_url(format: :json)
          }
        },
        {
          id: "nav-clips",
          label: "Clips",
          action: {}
        },
        {
          id: "nav-explore",
          label: "Explore",
          action: {
            type: "search",
            target: gatekeeper_search_url(format: :json)
          }
        }
      ]
    },
    hero: {
      component_type: "hero",
      id: "lightek-hero",
      title: "Welcome to Lightek",
      subtitle: "Culture. Community. Creators. Television.",
      description: "Move through the people, communities, live moments, and original programming shaping Lightek.",
      background_image_url: roku_image_url("hero-background.jpg"),
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

def live
  render json: {
    schema_version: API_VERSION,
    screen: {
      id: "live",
      type: "channel",
      title: "Watch",
      background_color: "#080808",
      refresh_after_seconds: 60,
      initial_focus: "watch-schedule"
    },

    details: {
      content_id: "featured-002",
      content_type: "live channel",
      is_live: true,
      title: "Lightek Television",
      subtitle: "Live across Lightek",
      description: "Original programming, culture, documentaries, creators, and community stories from across the Lightek network.",
      background_image_url: roku_image_url("lightek-live.jpg"),
      badge: "LIVE",
      indicator: {
        type: "status_dot",
        color: "#FF3B30"
      },
      metadata: {
        duration: "24/7",
        genre: "Lightek Television"
      },
      actions: [
        play_action(
          id: "live-watch",
          label: "Watch Live",
          content_id: "featured-002",
          playback_url: LIVE_PLAYBACK_URL
        )
      ]
    },

    rows: [
      {
        component_type: "content_row",
        id: "watch-schedule",
        title: "On Now & Up Next",
        activity_type: "live",
        eyebrow: "ON AIR",
        context: "Live now and coming up on Lightek",
        card_type: "landscape_card",
        card_width: 300,
        card_height: 169,
        items: [
          {
            id: "live-now",
            content_type: "live channel",
            is_live: true,
            title: "Lightek Live",
            subtitle: "On Now",
            description: "Watch the Lightek network live.",
            image_url: roku_image_url("lightek-live.jpg"),
            hero_image_url: roku_image_url("lightek-live.jpg"),
            badge: "LIVE",
            indicator: { type: "status_dot", color: "#FF3B30" },
            action: play_action(
              id: "live-now-watch",
              label: "Watch Live",
              content_id: "featured-002",
              playback_url: LIVE_PLAYBACK_URL
            )
          },
          {
            id: "featured-001",
            content_type: "documentary",
            title: "Featured Documentary",
            subtitle: "Up Next",
            description: "Meet the builders creating durable institutions and community-owned futures.",
            image_url: roku_image_url("featured-documentary.jpg"),
            hero_image_url: roku_image_url("featured-documentary.jpg"),
            badge: "NEXT",
            action: details_action("featured-001")
          },
          {
            id: "documentary-001",
            content_type: "documentary series",
            title: "The Resistance Economy",
            subtitle: "Later Today",
            description: "Ownership, labor, and community power.",
            image_url: roku_image_url("resistance-economy-poster.jpg"),
            hero_image_url: roku_image_url("hero-background.jpg"),
            action: details_action("documentary-001")
          }
        ]
      },

      {
        component_type: "content_row",
        id: "watch-live-channels",
        title: "Live Channels",
        activity_type: "live",
        eyebrow: "LIVE TV",
        context: "Channels broadcasting across the Lightek network",
        card_type: "landscape_card",
        card_width: 420,
        card_height: 236,
        items: [
          {
            id: "lightek-live-channel",
            content_type: "live channel",
            is_live: true,
            title: "Lightek Live",
            subtitle: "24/7 Network",
            description: "The continuous Lightek television feed.",
            image_url: roku_image_url("lightek-live.jpg"),
            hero_image_url: roku_image_url("lightek-live.jpg"),
            badge: "LIVE",
            action: play_action(
              id: "lightek-live-channel-watch",
              label: "Watch Live",
              content_id: "featured-002",
              playback_url: LIVE_PLAYBACK_URL
            )
          }
        ]
      },

      {
        component_type: "content_row",
        id: "watch-originals",
        title: "Lightek Originals",
        activity_type: "program",
        eyebrow: "ORIGINALS",
        context: "Stories and programs made by Lightek",
        card_type: "landscape_card",
        card_width: 420,
        card_height: 236,
        items: [
          {
            id: "original-featured-documentary",
            content_type: "documentary",
            title: "Featured Documentary",
            subtitle: "Lightek Original",
            description: "A creator-led original about durable institutions and community-owned futures.",
            image_url: roku_image_url("featured-documentary.jpg"),
            hero_image_url: roku_image_url("featured-documentary.jpg"),
            action: details_action("featured-001")
          },
          {
            id: "original-resistance-economy",
            content_type: "documentary series",
            title: "The Resistance Economy",
            subtitle: "Lightek Original Series",
            description: "A series about ownership, labor, and community power.",
            image_url: roku_image_url("resistance-economy-poster.jpg"),
            hero_image_url: roku_image_url("hero-background.jpg"),
            action: details_action("documentary-001")
          }
        ]
      },

      {
        component_type: "content_row",
        id: "watch-documentaries",
        title: "Documentaries & Specials",
        activity_type: "program",
        eyebrow: "FEATURED",
        context: "Films, specials, and stories worth sitting with",
        card_type: "landscape_card",
        card_width: 420,
        card_height: 236,
        items: [
          {
            id: "documentary-feature",
            content_type: "documentary",
            title: "Featured Documentary",
            subtitle: "Documentary",
            description: "Meet the builders creating durable institutions and community-owned futures.",
            image_url: roku_image_url("featured-documentary.jpg"),
            hero_image_url: roku_image_url("featured-documentary.jpg"),
            action: details_action("featured-001")
          },
          {
            id: "resistance-feature",
            content_type: "documentary series",
            title: "The Resistance Economy",
            subtitle: "Documentary Series",
            description: "Ownership, labor, and community power.",
            image_url: roku_image_url("resistance-economy-poster.jpg"),
            hero_image_url: roku_image_url("hero-background.jpg"),
            action: details_action("documentary-001")
          }
        ]
      },

      {
        component_type: "content_row",
        id: "watch-continue",
        title: "Continue Watching",
        activity_type: "continue",
        eyebrow: "PICK UP",
        context: "Resume where you left off",
        card_type: "landscape_card",
        card_width: 420,
        card_height: 236,
        items: [
          {
            id: "continue-featured",
            content_type: "documentary",
            title: "Featured Documentary",
            subtitle: "Continue Watching",
            description: "Continue your Lightek Original.",
            image_url: roku_image_url("featured-documentary.jpg"),
            hero_image_url: roku_image_url("featured-documentary.jpg"),
            progress: 0.38,
            action: details_action("featured-001")
          },
          {
            id: "continue-resistance",
            content_type: "documentary series",
            title: "The Resistance Economy",
            subtitle: "Continue Watching",
            description: "Return to the series.",
            image_url: roku_image_url("resistance-economy-poster.jpg"),
            hero_image_url: roku_image_url("hero-background.jpg"),
            progress: 0.67,
            action: details_action("documentary-001")
          }
        ]
      }
    ],

    metadata: response_metadata
  }
end

  def search
    query = params[:q].to_s.strip
    normalized_query = query.downcase
    results =
      if normalized_query.blank?
        search_catalog
      else
        search_catalog.select do |item|
          [
            item[:title],
            item[:subtitle],
            item[:description],
            item[:content_type]
          ].compact.any? { |value| value.downcase.include?(normalized_query) }
        end
      end

    title = query.blank? ? "Discover Lightek" : "Results for “#{query}”"
    description =
      if results.any?
        "#{results.length} #{results.length == 1 ? 'result' : 'results'} from across the Lightek network."
      else
        "No matches yet. Press Back and search for another title, genre, or channel."
      end

    render json: {
      schema_version: API_VERSION,
      screen: {
        id: "search",
        type: "search",
        title: title,
        background_color: "#080808"
      },
      details: {
        content_id: "search",
        content_type: "search",
        title: title,
        subtitle: query.blank? ? "Explore the network" : "Search",
        description: description,
        background_image_url: roku_image_url("hero-background.jpg"),
        metadata: {
          genre: "Lightek FAST"
        },
        actions: []
      },
      rows: results.any? ? [
        {
          component_type: "content_row",
          id: "search-results",
          title: query.blank? ? "Explore" : "Search Results",
          card_type: "landscape_card",
          card_width: 300,
          card_height: 169,
          items: results
        }
      ] : [],
      search: {
        query: query,
        endpoint: gatekeeper_search_url(format: :json)
      },
      metadata: response_metadata
    }
  end

  #TV Guide / EPG Endpoint
  # GET /gatekeeper/guide.json
  def guide
    render json:{
  "screen": {
    "id": "guide",
    "type": "tv_guide",
    "title": "LBN Guide"
  },
  "channels": [
    {
      "id": "lbn-originals",
      "number": "101",
      "name": "LBN Originals",
      "logo": "/images/channels/lbn-originals.png",
      "schedule": [
        {
          "start_time": "2026-08-07T20:00:00Z",
          "end_time": "2026-08-07T21:00:00Z",
          "title": "The Resistance Economy",
          "episode": "Episode 1",
          "content_id": "documentary-001"
        },
        {
          "start_time": "2026-08-07T21:00:00Z",
          "end_time": "2026-08-07T22:00:00Z",
          "title": "LBN Live",
          "content_id": "live-001"
        }
      ]
    }
  ]
}
  end

  #Channel Lineup
  #GET /channels.json
  def channels
    render json: {
  "channels": [
    {
      "number": 100,
      "call_sign": "LBN",
      "name": "Lightek Network",
      "type": "fast",
      "live": true
    },
    {
      "number": 101,
      "call_sign": "LBN-DOC",
      "name": "LBN Documentaries",
      "type": "fast",
      "live": true
    }
  ]
}
  end

  #Master Control State
  #GET /master_control.json

  def master_control
    render json: {
  "channels": [
    {
      "channel": "LBN Originals",
      "status": "on_air",
      "current_program": {
        "title": "The Resistance Economy",
        "remaining_seconds": 1432
      },
      "next_program": {
        "title": "Community Builders"
      }
    }
  ]
}
  end

  #Content Submission Pipeline
#This connects the creator side.
#The flow: 
#Creator>Submit Program>Review>Approved>Scheduled>Broadcast

def creator_submission
  render json: {
 "submission": {
   "id": "submission-001",
   "status": "approved",
   "eligible_channels": [
     "LBN Originals",
     "LBN Community"
   ]
 }
}
end

#Scheduler
#GET /scheduler.json

def scheduler
  render json: {
 "schedule_date":"2026-08-07",
 "slots":[
   {
     "channel":"LBN Comedy",
     "time":"8:00 PM",
     "program":"Creator Showcase",
     "status":"scheduled"
   }
 ]
}
end

#EPG schema

def epg
#LBN Guide Protocol

#Channel
#Program
#Episode
#Air Time
#Duration
#Genre
#Rating
#Description
#Artwork
#Playback Source
#Availability Window
end

#Stations
#This is different from channels.
#You mentioned public access.


#Distribution

def distribution
  render json: {
    "program":"Creator Showcase",

    "destinations":[

        {
            "type":"roku"
        },

        {
            "type":"apple_tv"
        },

        {
            "type":"android_tv"
        },

        {
            "type":"public_access"
        },

        {
            "type":"web"
        }

    ]
}
end

#Clock
#Server time the external devices should all be checking versus internal device clocks

def clock
  render json: {
    "utc":"2026-08-07T18:25:11Z",

    "broadcast_day":"2026-08-07",

    "frame":"running"
}
end

  def search_catalog
    [
      {
        id: "featured-001",
        content_type: "documentary",
        title: "Featured Documentary",
        subtitle: "Lightek Originals",
        description: "Meet the builders creating durable institutions and community-owned futures.",
        image_url: roku_image_url("featured-documentary.jpg"),
        hero_image_url: roku_image_url("featured-documentary.jpg"),
        badge: "NEW",
        action: details_action("featured-001")
      },
      {
        id: "featured-002",
        content_type: "live channel",
        is_live: true,
        title: "Lightek Live",
        subtitle: "Streaming now",
        description: "Watch the Lightek network live.",
        image_url: roku_image_url("lightek-live.jpg"),
        hero_image_url: roku_image_url("lightek-live.jpg"),
        badge: "LIVE",
        indicator: {
          type: "status_dot",
          color: "#FF3B30"
        },
        action: play_action(
          id: "search-live-watch",
          label: "Watch Live",
          content_id: "featured-002",
          playback_url: LIVE_PLAYBACK_URL
        )
      },
      {
        id: "documentary-001",
        content_type: "documentary series",
        title: "The Resistance Economy",
        subtitle: "Season 1",
        description: "A documentary series about ownership, labor, and community power.",
        image_url: roku_image_url("resistance-economy-poster.jpg"),
        hero_image_url: roku_image_url("hero-background.jpg"),
        action: details_action("documentary-001")
      }
    ]
  end

def home_rows
  [
    {
      component_type: "content_row",
      id: "people-you-follow",
      title: "From People You Follow",
      card_type: "landscape_card",
      card_width: 420,
      card_height: 236,
      items: [
        {
          id: "featured-001",
          content_type: "creator program",
          title: "Featured Documentary",
          subtitle: "Lightek Originals",
          description: "A creator-led Lightek original about building durable institutions and community-owned futures.",
          image_url: roku_image_url("featured-documentary.jpg"),
          hero_image_url: roku_image_url("featured-documentary.jpg"),
          badge: "NEW",
          duration_seconds: 2700,
          action: details_action("featured-001")
        },
        {
          id: "documentary-001",
          content_type: "creator series",
          title: "The Resistance Economy",
          subtitle: "Season 1",
          description: "Ownership, labor, culture, and community power from inside the Lightek network.",
          image_url: roku_image_url("resistance-economy-poster.jpg"),
          hero_image_url: roku_image_url("hero-background.jpg"),
          action: details_action("documentary-001")
        },
        {
          id: "featured-002",
          content_type: "live creator channel",
          is_live: true,
          title: "Lightek Live",
          subtitle: "Streaming now",
          description: "Creators, original programming, culture, and community stories live across Lightek.",
          image_url: roku_image_url("lightek-live.jpg"),
          hero_image_url: roku_image_url("lightek-live.jpg"),
          badge: "LIVE",
          indicator: {
            type: "status_dot",
            color: "#FF3B30"
          },
          action: play_action(
            id: "people-follow-live",
            label: "Watch Live",
            content_id: "featured-002",
            playback_url: LIVE_PLAYBACK_URL
          )
        }
      ]
    },
    {
      component_type: "content_row",
      id: "live-right-now",
      title: "Live Right Now",
      card_type: "landscape_card",
      card_width: 360,
      card_height: 203,
      items: [
        {
          id: "live-now",
          content_type: "live channel",
          is_live: true,
          title: "Lightek Live",
          subtitle: "On Now",
          description: "The network is live.",
          image_url: roku_image_url("lightek-live.jpg"),
          hero_image_url: roku_image_url("lightek-live.jpg"),
          badge: "LIVE",
          indicator: {
            type: "status_dot",
            color: "#FF3B30"
          },
          action: play_action(
            id: "home-live-watch",
            label: "Watch Live",
            content_id: "featured-002",
            playback_url: LIVE_PLAYBACK_URL
          )
        },
        {
          id: "live-featured-next",
          content_type: "network premiere",
          title: "Featured Documentary",
          subtitle: "Up Next",
          description: "Lightek programming moving from the social network into the television schedule.",
          image_url: roku_image_url("featured-documentary.jpg"),
          hero_image_url: roku_image_url("featured-documentary.jpg"),
          badge: "NEXT",
          action: details_action("featured-001")
        }
      ]
    },
    {
      component_type: "content_row",
      id: "your-communities",
      title: "From Your Communities",
      card_type: "landscape_card",
      card_width: 360,
      card_height: 203,
      items: [
        {
          id: "community-ownership",
          content_type: "community program",
          title: "Ownership & Community",
          subtitle: "Community Spotlight",
          description: "Programming, conversations, and people organized around ownership and durable local power.",
          image_url: roku_image_url("resistance-economy-poster.jpg"),
          hero_image_url: roku_image_url("hero-background.jpg"),
          action: details_action("documentary-001")
        },
        {
          id: "community-builders",
          content_type: "community feature",
          title: "Community Builders",
          subtitle: "Across Lightek",
          description: "Meet the people building culture and institutions inside the network.",
          image_url: roku_image_url("featured-documentary.jpg"),
          hero_image_url: roku_image_url("featured-documentary.jpg"),
          action: details_action("featured-001")
        }
      ]
    },
    {
      component_type: "content_row",
      id: "trending-clips",
      title: "Trending Clips",
      card_type: "landscape_card",
      card_width: 300,
      card_height: 169,
      items: [
        {
          id: "clip-live-moment",
          content_type: "clip",
          title: "Live Moment",
          subtitle: "From Lightek Live",
          description: "Short-form discovery enters the television experience.",
          image_url: roku_image_url("lightek-live.jpg"),
          hero_image_url: roku_image_url("lightek-live.jpg"),
          badge: "CLIP",
          action: play_action(
            id: "clip-live-play",
            label: "Play Clip",
            content_id: "featured-002",
            playback_url: LIVE_PLAYBACK_URL
          )
        },
        {
          id: "clip-featured-moment",
          content_type: "clip",
          title: "Builder Story",
          subtitle: "Featured Clip",
          description: "A short moment from a Lightek original.",
          image_url: roku_image_url("featured-documentary.jpg"),
          hero_image_url: roku_image_url("featured-documentary.jpg"),
          badge: "CLIP",
          action: play_action(
            id: "clip-featured-play",
            label: "Play Clip",
            content_id: "featured-stream",
            playback_url: FEATURED_PLAYBACK_URL
          )
        },
        {
          id: "clip-resistance-moment",
          content_type: "clip",
          title: "The Work Begins",
          subtitle: "The Resistance Economy",
          description: "A short-form entry point into the series.",
          image_url: roku_image_url("resistance-economy-poster.jpg"),
          hero_image_url: roku_image_url("hero-background.jpg"),
          badge: "CLIP",
          action: play_action(
            id: "clip-resistance-play",
            label: "Play Clip",
            content_id: "documentary-001-episode-001",
            playback_url: FEATURED_PLAYBACK_URL
          )
        }
      ]
    },
    {
      component_type: "content_row",
      id: "continue-watching",
      title: "Continue Watching",
      card_type: "landscape_card",
      card_width: 360,
      card_height: 203,
      items: [
        {
          id: "continue-resistance",
          content_type: "series",
          title: "The Resistance Economy",
          subtitle: "Continue Season 1",
          description: "Return to the series without leaving the wider Lightek experience.",
          image_url: roku_image_url("resistance-economy-poster.jpg"),
          hero_image_url: roku_image_url("hero-background.jpg"),
          action: details_action("documentary-001")
        },
        {
          id: "continue-featured",
          content_type: "documentary",
          title: "Featured Documentary",
          subtitle: "Continue Watching",
          description: "Pick up where you left off.",
          image_url: roku_image_url("featured-documentary.jpg"),
          hero_image_url: roku_image_url("featured-documentary.jpg"),
          action: details_action("featured-001")
        }
      ]
    },
    {
      component_type: "content_row",
      id: "creators-to-know",
      title: "Creators You Should Know",
      card_type: "landscape_card",
      card_width: 300,
      card_height: 169,
      items: [
        {
          id: "creator-network-live",
          content_type: "creator channel",
          title: "Lightek Live",
          subtitle: "Network Creator Channel",
          description: "Follow programming as a living channel, not just a title in a catalog.",
          image_url: roku_image_url("lightek-live.jpg"),
          hero_image_url: roku_image_url("lightek-live.jpg"),
          action: play_action(
            id: "creator-live-watch",
            label: "Watch",
            content_id: "featured-002",
            playback_url: LIVE_PLAYBACK_URL
          )
        },
        {
          id: "creator-resistance",
          content_type: "creator series",
          title: "The Resistance Economy",
          subtitle: "Lightek Original",
          description: "A first look at how creator identities can become television channels inside Lightek.",
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
              description: "A documentary series about ownership, labor, and community power.",
              image_url: roku_image_url("resistance-economy-poster.jpg"),
              hero_image_url: roku_image_url("hero-background.jpg"),
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
            label: "Watch Episode",
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
              hero_image_url: roku_image_url("featured-documentary.jpg"),
              badge: "NEW",
              action: play_action(
                id: "episode-001-play",
                label: "Play",
                content_id: "documentary-001-episode-001",
                playback_url: FEATURED_PLAYBACK_URL
              )
            },
            {
              id: "documentary-001-episode-002",
              content_type: "episode",
              title: "Episode 2",
              subtitle: "Building the Network",
              description: "The work expands from individual builders into a connected community network.",
              image_url: roku_image_url("lightek-live.jpg"),
              hero_image_url: roku_image_url("lightek-live.jpg"),
              action: play_action(
                id: "episode-002-play",
                label: "Play",
                content_id: "documentary-001-episode-002",
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
      target: gatekeeper_content_url(id: content_id, format: :json)
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

