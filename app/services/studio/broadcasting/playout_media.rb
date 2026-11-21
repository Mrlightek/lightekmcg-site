# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module Studio
  module Broadcasting
    class PlayoutMedia
      Segment = Data.define(:key, :path, :duration)
      SCALE = "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,setsar=1"
      CODECS = %w[-c:v libx264 -preset ultrafast -tune zerolatency -threads 2 -pix_fmt yuv420p -r 24 -g 48 -keyint_min 48 -sc_threshold 0
        -b:v 1300k -maxrate 1300k -bufsize 2600k -c:a aac -b:a 96k -ar 44100 -ac 2].freeze
      FILE_NAME = /\Asegment-\d+\.ts\z/
      def self.root = Rails.root.join("storage", "studio-playout")
      def self.channel_path(id) = root.join("channels", Integer(id).to_s)
      def self.airing_path(id) = root.join("airings", Integer(id).to_s)
      def self.ffmpeg = ENV.fetch("LIGHTEK_FFMPEG", "ffmpeg")

      def self.prepare!(airing)
        root = airing_path(airing.id)
        FileUtils.mkdir_p(root, mode: 0o700)
        File.open(root.join("prepare.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          return unless lock.flock(File::LOCK_EX | File::LOCK_NB) && airing.reload.status == "preparing"
          actor = Studio::PwaAccess.new("user_id" => airing.operator_id, "site_id" => airing.channel.site_id)
          Studio::Broadcasting::Access.authorize!(airing.operator, airing.channel.site)
          airing.touch
          airing.rundown.each_with_index do |item, index|
            asset = if item["license_id"]
              license = ProgramLicense.where(licensee_site_id: airing.channel.site_id).find(item["license_id"])
              unless license.asset_id == item["asset_id"] && license.covers?(airing.starts_at, airing.ends_at) &&
                  license.allows_use?(item.fetch("license_use", "air")) && airing.relay.blank?
                raise ArgumentError, "A licensed source is unavailable for this airing."
              end
              license.asset
            else
              StudioAsset.for_actor(actor).where(site_id: airing.channel.site_id, status: "ready", kind: "video").find(item.fetch("asset_id"))
            end
            raise ArgumentError, "A scheduled source has changed." unless asset.proxy.attached? && asset.proxy.blob.id == item.fetch("blob_id")
            heartbeat = Time.current
            still_preparing = lambda do
              next false if Time.current - heartbeat < 2
              heartbeat = Time.current
              airing.reload.status != "preparing" || !Airing.where(id: airing.id, status: "preparing").update_all(updated_at: heartbeat).positive?
            end
            asset.proxy.blob.open(tmpdir: Studio::MediaProcess.temp_root) do |source|
              encode!(root.join(index.to_s), source: source.path, seconds: item.fetch("seconds"), sponsor: item.fetch("sponsor"),
                audio: asset.metadata["has_audio"], cancel_if: still_preparing)
            end
            prepare_ad!(airing, index, root, still_preparing) if item["ad_campaign_id"]
          end
          airing.with_lock { airing.update!(status: "ready") if airing.status == "preparing" }
        end
      end

      def self.prepare_ad!(airing, index, root, cancel_if)
        placement = Advertising::Placement.find_by(airing_id: airing.id, row_index: index)
        campaign = placement&.campaign
        directory = root.join("ad-#{index}")
        # A retried preparation must never reuse a stale campaign playlist.
        FileUtils.rm_f(directory.join("index.m3u8"))
        return unless campaign&.creative_available?

        campaign.asset.proxy.blob.open(tmpdir: Studio::MediaProcess.temp_root) do |source|
          encode!(directory, source: source.path, seconds: campaign.seconds,
            audio: campaign.asset.metadata["has_audio"], cancel_if: cancel_if)
        end
      rescue StandardError => error
        Rails.logger.warn("[StudioPlayout] airing=#{airing.id} ad_row=#{index} backup=true error=#{error.class}")
      end
      private_class_method :prepare_ad!

      def self.standby(channel_id)
        path = channel_path(channel_id).join("standby")
        encode!(path, seconds: 2) unless path.join("index.m3u8").file?
        segments(path).first || raise("Standby media is unavailable")
      end

      def self.feed_health(channel_id)
        playlist = channel_path(channel_id).join("index.m3u8")
        return "No feed yet" unless playlist.file?
        return "Between airings" if playlist.read.include?("#EXT-X-ENDLIST")

        playlist.mtime > 12.seconds.ago ? "Sending video" : "Feed stalled"
      rescue Errno::ENOENT
        "No feed yet"
      end

      def self.backup(channel)
        return if channel.backup_asset_id.nil? || channel.backup_blob_id.nil?
        return unless StudioAsset.exists?(id: channel.backup_asset_id, site_id: channel.site_id, kind: "video", status: "ready")

        segments(backup_path(channel.id, channel.backup_asset_id, channel.backup_blob_id))
      end

      def self.prepare_backup!(channel, asset_id, blob_id)
        return unless channel.backup_asset_id == asset_id && channel.backup_blob_id == blob_id

        asset = StudioAsset.where(site_id: channel.site_id, status: "ready", kind: "video").find(asset_id)
        return unless asset.proxy.attached? && asset.proxy.blob.id == blob_id

        seconds = [asset.metadata["duration"].to_f.floor, 60].min
        return if seconds < 2

        directory = backup_path(channel.id, asset_id, blob_id)
        asset.proxy.blob.open(tmpdir: Studio::MediaProcess.temp_root) do |source|
          encode!(directory, seconds: seconds, source: source.path, audio: asset.metadata["has_audio"])
        end
      end

      def self.backup_path(channel_id, asset_id, blob_id)
        channel_path(channel_id).join("backup-#{Integer(asset_id)}-#{Integer(blob_id)}")
      end
      private_class_method :backup_path

      def self.encode!(directory, seconds:, source: nil, audio: false, sponsor: "", cancel_if: nil)
        FileUtils.mkdir_p(directory, mode: 0o700)
        Dir.mktmpdir("encode-", directory) do |temp|
          filters = [SCALE, "tpad=stop_mode=clone:stop_duration=2"]
          if sponsor.present?
            text_path = File.join(temp, "sponsor.txt")
            File.write(text_path, sponsor)
            filters << "drawtext=textfile='#{text_path.gsub(/[':\\]/) { |character| "\\#{character}" }}':expansion=none:fontsize=29:fontcolor=white:box=1:boxcolor=black@0.8:boxborderw=14:x=46:y=h-th-46"
          end
          command = [ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-nostdin", "-filter_threads", "1"]
          command += if source
            ["-protocol_whitelist", "file", "-format_whitelist", "mov,mp4,m4a,3gp,3g2,mj2,matroska,webm,mpegts,avi,mpeg", "-threads", "2", "-i", source]
          else
            %w[-f lavfi -i color=c=0x101821:s=1280x720:r=24]
          end
          command += %w[-f lavfi -i anullsrc=r=44100:cl=stereo] unless audio
          command += ["-map", "0:v:0", "-map", audio ? "0:a:0" : "1:a:0", "-vf", filters.join(","), "-af", "apad",
            "-t", seconds.to_s, *CODECS, "-f", "hls", "-hls_time", "2", "-hls_list_size", "0", "-hls_flags", "independent_segments",
            "-hls_segment_filename", File.join(temp, "segment-%06d.ts"), File.join(temp, "index.m3u8")]
          Studio::MediaProcess.run!(command, timeout: [seconds * 3 + 60, 24_000].min, cancel_if: cancel_if)
          media = segments(Pathname(temp))
          raise "Prepared media is shorter than the rundown slot" if media.sum(&:duration) < seconds - 0.1
          media.each { |segment| File.rename(segment.path, directory.join(segment.key)) }
          File.rename(File.join(temp, "index.m3u8"), directory.join("index.m3u8"))
        end
      end

      def self.segments(directory, include_missing: false)
        duration = nil
        directory.join("index.m3u8").read.lines(chomp: true).filter_map do |line|
          if line.start_with?("#EXTINF:")
            duration = Float(line.delete_prefix("#EXTINF:").split(",").first)
            next
          elsif FILE_NAME.match?(line) && duration&.positive?
            path = directory.join(line)
            Segment.new(line, path, duration) if include_missing || path.file?
          end
        end
      rescue Errno::ENOENT
        []
      end
    end
  end
end
