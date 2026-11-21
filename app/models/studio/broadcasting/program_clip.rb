# frozen_string_literal: true

module Studio
  module Broadcasting
    class ProgramClip < ApplicationRecord
      self.table_name = "studio_program_clips"
      MAX_BYTES = 24.megabytes

      belongs_to :site, class_name: "DymondSite::Site"
      belongs_to :license, class_name: "Studio::Broadcasting::ProgramLicense"
      has_one_attached :video
      has_secure_token :public_key, length: 32

      attr_readonly :site_id, :license_id, :title, :start_second, :duration_seconds, :public_key
      validates :title, presence: true, length: { maximum: 120 }
      validates :start_second, numericality: { only_integer: true, in: 0..7200 }
      validates :duration_seconds, numericality: { only_integer: true, in: 2..60 }
      validate :valid_source, on: :create

      def playable?
        !withdrawn_at? && error_message.blank? && video.attached? && video.blob.byte_size.between?(1, MAX_BYTES) && licensed_now?
      end

      def licensed_now?
        now = Time.current
        return false unless license.licensee_site_id == site_id && license.permits?(now, now, use: "clip") &&
          license.allows_destination?(["web"], ["WORLDWIDE"])

        HostedPrograms.check_booking!(license)
        true
      rescue HostedPrograms::Unavailable, LightekReservations::Federation::Client::Unavailable
        false
      end

      def prepare!
        return if video.attached? || withdrawn_at?
        raise ArgumentError, "Clip rights are no longer available." unless licensed_now?

        Studio::MediaProcess.temporary_directory("broadcast-clip-") do |directory|
          output = File.join(directory, "clip.mp4")
          license.asset.proxy.blob.open do |file|
            Studio::MediaProcess.run!([PlayoutMedia.ffmpeg, "-nostdin", "-v", "error", "-protocol_whitelist", "file",
              "-format_whitelist", "mov,mp4,m4a,3gp,3g2,mj2", "-ss", start_second.to_s, "-threads", "2", "-i", file.path,
              "-t", duration_seconds.to_s, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", "-vf", PlayoutMedia::SCALE,
              "-filter_threads", "1", "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p", "-threads", "2",
              "-b:v", "1500k", "-maxrate", "2000k", "-bufsize", "4000k", "-c:a", "aac", "-b:a", "96k",
              "-movflags", "+faststart", "-f", "mp4", output], timeout: 170)
          end
          raise ArgumentError, "The clip exceeded the media size limit." unless File.size(output).between?(1, MAX_BYTES)

          File.open(output, "rb") do |file|
            with_lock do
              next if video.attached? || withdrawn_at?
              raise ArgumentError, "Clip rights are no longer available." unless licensed_now?

              video.attach(io: file, filename: "broadcast-clip.mp4", content_type: "video/mp4", identify: false)
              update!(error_message: nil) if error_message?
            end
          end
        end
      end

      private

      def valid_source
        errors.add(:license, "must include current clip rights for this station") unless license && licensed_now?
        return unless start_second && duration_seconds && license&.asset

        if start_second + duration_seconds > license.asset.metadata["duration"].to_f
          errors.add(:duration_seconds, "would go past the end of the licensed video")
        end
      end
    end
  end
end
