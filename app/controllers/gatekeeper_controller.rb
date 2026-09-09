# app/controllers/gatekeeper_controller.rb

class GatekeeperController < ApplicationController
  allow_unauthenticated_access

  API_VERSION = "1.0".freeze
  LIGHTEK_ENV = Rails.env
  LIGHTEK_NETWORK_LISTENER = :listener
  LIGHTEK_SERVER = :server
  LIGHTEK_PLATFORM_ID = "com.lightekmcg.fast"
  LIGHTEK_PLATFORM_NAME = "Lightek FAST"
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

   # The single entry point / router method
  def octavia

    # 1. Grab the target method name from parameters
    target_action = params[:method_type] 

    # 2. Whitelist allowed methods to prevent malicious code execution
    allowed_actions = LIGHTEK_ALLOWED_ACTIONS

    if allowed_actions.include?(target_action)
      # 3. Dynamically invoke the method and return its JSON response
      render json: send(target_action)
    else
      render json: LIGHTEK_REQUEST_ERROR, status: :bad_request
    end
  end

  
  private
    
    def listener
    listener = NetworkListener.new
    listener.start
    end
    
    def web_hook
    #Assign all web hooks here.
    #Start with listeners on all incomming traffic ports
    #This is our ip router function.
    #Example: mail comes in on port 25, we route that to our custom mail functions
    
    end

    def outbound
      #Assign all outbound requests here
      #Example: any outbound server, external, internal-external
      end
    
    def server
    # get all server specs possible
    #name, all ip, everything
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
    %w[fetch_users fetch_inventory update_settings delete_cache]
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
        home: kitchen_sink_url(format: :json)
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
              target: roku_live_url(format: :json)
            }
          },
          {
            id: "nav-search",
            label: "Search",
            action: {
              type: "search",
              target: roku_search_url(format: :json)
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

  def live
    render json: {
      schema_version: API_VERSION,
      screen: {
        id: "live",
        type: "channel",
        title: "Lightek Live",
        background_color: "#080808",
        refresh_after_seconds: 60
      },
      details: {
        content_id: "featured-002",
        content_type: "live channel",
        is_live: true,
        title: "Lightek Live",
        subtitle: "Streaming now",
        description: "The Lightek network live—original programming, culture, documentaries, and community stories in one continuous stream.",
        background_image_url: roku_image_url("lightek-live.jpg"),
        badge: "LIVE",
        indicator: {
          type: "status_dot",
          color: "#FF3B30"
        },
        metadata: {
          duration: "24/7",
          genre: "Live Programming"
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
          id: "live-schedule",
          title: "On Now & Up Next",
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
              indicator: {
                type: "status_dot",
                color: "#FF3B30"
              },
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
              description: "A documentary series about ownership, labor, and community power.",
              image_url: roku_image_url("resistance-economy-poster.jpg"),
              hero_image_url: roku_image_url("hero-background.jpg"),
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
        endpoint: roku_search_url(format: :json)
      },
      metadata: response_metadata
    }
  end

  #TV Guide / EPG Endpoint
  #GET /kitchen_sink/guide.json
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

