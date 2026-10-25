namespace :studio_live do
  desc "Check the server-side browser broadcasting dependencies"
  task doctor: :environment do
    abort "FFmpeg is missing. Run lib/scripts/install_lightek_live_encoder.sh on the application server." unless Studio::Live::Encoder.available?
    encoders, result = Open3.capture2(ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg"), "-hide_banner", "-encoders", err: File::NULL)
    abort "FFmpeg requires libx264 and AAC encoders." unless result.success? && encoders.include?("libx264") && encoders.match?(/\baac\b/)
    puts "LIGHTEK_LIVE_ENCODER_READY"
    puts "Open /dashboard/live over HTTPS and run a private test to verify browser permissions and WebSocket routing."
  end
  desc "Remove private test recordings older than 24 hours and mark abandoned browser sessions failed"
  task cleanup: :environment do
    directory = Rails.root.join("tmp", "studio_live")
    removed = 0
    if directory.directory?
      directory.children.each do |file|
        next unless file.basename.to_s.match?(/\A\d+\.mp4\z/) && file.file? && file.mtime < 24.hours.ago
        file.delete
        removed += 1
      end
    end
    expired = Studio::Live::Sessions.scope.where(status: %w[draft connecting live]).where("updated_at < ?", 45.seconds.ago).update_all(status: "failed", error_message: "Capture connection expired.", ended_at: Time.current)
    puts "Removed #{removed} expired recordings; expired #{expired} abandoned sessions."
  end
end
