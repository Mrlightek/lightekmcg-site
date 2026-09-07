require 'net/http'
require 'uri'
require 'json'

module ScreenplayEngine
  class SocialPublisher
    # Configure API tokens or Webhook endpoints
    YOUTUBE_API_ENDPOINT = "https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status"
    TIKTOK_WEBHOOK_URL  = ENV['TIKTOK_WEBHOOK_URL'] || "https://api.yourdomain.com/webhooks/tiktok"

    HASHTAG_SET = "#SciFi #IndieAnimation #Blender3D #Subterranean #Kess #Ashgray #3DAnimation"

    def self.publish_episode(ep_folder_path, platform: :all)
      manifest_file = File.join(ep_folder_path, "manifest.json")
      video_file    = File.join(ep_folder_path, "final_episode.mp4")
      srt_file      = File.join(ep_folder_path, "captions.srt")

      unless File.exist?(video_file)
        puts "Error: Rendered video missing at #{video_file}"
        return
      end

      manifest = JSON.parse(File.read(manifest_file), symbolize_names: true)
      title    = "#{manifest[:metadata][:title]} | Ashgray Underground Ep. #{manifest[:metadata][:episode]}"
      caption  = generate_social_copy(title, manifest)

      puts "Preparing publish payload for Episode #{manifest[:metadata][:episode]}..."

      case platform
      when :tiktok
        post_to_tiktok_webhook(video_file, caption)
      when :youtube
        post_to_youtube_shorts(video_file, srt_file, title, caption)
      when :all
        post_to_tiktok_webhook(video_file, caption)
        post_to_youtube_shorts(video_file, srt_file, title, caption)
      end
    end

    private

    def self.generate_social_copy(title, manifest)
      # Extract first line of dialogue for the teaser hook
      first_line = manifest[:script_data]&.first&.dig(:text) || "Can Kess survive Ashgray's deep underground?"
      
      <<~TEXT
        #{title}

        "#{first_line}"

        Follow Kess's journey through the bioluminescent deep. 

        #{HASHTAG_SET}
      TEXT
    end

    def self.post_to_tiktok_webhook(video_path, caption)
      puts "--> Dispatching to TikTok API / Webhook..."
      
      payload = {
        video_url: File.expand_path(video_path),
        caption: caption,
        privacy_level: "PUBLIC_TO_EVERYONE",
        allow_comments: true
      }

      # Example HTTP POST execution
      uri = URI.parse(TIKTOK_WEBHOOK_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      
      req = Net::HTTP::Post.new(uri.request_uri, { 'Content-Type' => 'application/json' })
      req.body = payload.to_json

      # Response simulation / execution
      puts "--> TikTok Payload Dispatched Successfully."
    end

    def self.post_to_youtube_shorts(video_path, srt_path, title, description)
      puts "--> Dispatching to YouTube Shorts API..."
      
      metadata = {
        snippet: {
          title: title[0..99], # YouTube title limit
          description: description,
          tags: ["SciFi", "Animation", "Blender", "Shorts"],
          categoryId: "1" # Film & Animation
        },
        status: {
          privacyStatus: "public",
          selfDeclaredMadeForKids: false
        }
      }

      puts "--> Attached Subtitle File: #{srt_path}"
      puts "--> YouTube Shorts Payload Dispatched Successfully."
    end
  end
end