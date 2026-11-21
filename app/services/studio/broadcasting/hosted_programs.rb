# frozen_string_literal: true

require "digest"
require "tempfile"

module Studio
  module Broadcasting
    module HostedPrograms
      class Unavailable < StandardError; end
      MAX_BYTES = 256.megabytes
      module_function

      def client(site) = LightekReservations::Federation::Client.new(site)

      def directory
        hub = URI.parse(LightekReservations::Federation::Issuer.origin).host
        ids = Channel.where(id: NetworkCarriage.accepted.select(:channel_id)).select(:site_id)
        hosted_ids = LightekReservations::Peer.where(id: HostedCarriage.available.select(:peer_id)).select(:site_id)
        DymondSite::Site.where(host: hub).or(DymondSite::Site.where(id: ids)).or(DymondSite::Site.where(id: hosted_ids))
      end

      def board(site)
        client(site).request("broadcast/programs")
      end

      def describe(record)
        { key: record.federation_key, title: record.title, source: record.source_name,
          starts_at: record.starts_at.iso8601, ends_at: record.ends_at.iso8601, status: record.status }
      end

      def reference!(record)
        record.with_lock do
          record.update!(federation_key: SecureRandom.hex(16)) unless record.federation_key?
          record.federation_key
        end
      end

      def publish!(site:, asset:, recipient:, title:, starts_at:, ends_at:)
        key = SecureRandom.hex(16)
        blob = asset.proxy.blob || raise(Unavailable, "Choose a ready MP4 video with a playback proxy.")
        raise Unavailable, "The program exceeds the 256 MB exchange limit." unless blob.byte_size.between?(1, MAX_BYTES)

        blob.open do |file|
          metadata = { recipient: recipient, title: title, starts_at: starts_at.iso8601, ends_at: ends_at.iso8601,
            sha256: Digest::SHA256.file(file.path).hexdigest }
          file.rewind
          client(site).broadcast_media("broadcast/programs/#{key}/media", upload: file, bytes: blob.byte_size, metadata: metadata)
        end
      end

      def receive!(peer, key, header, input, length)
        values = JSON.parse(header.to_s)
        target = directory.where.not(id: peer.site_id).find(values.fetch("recipient"))
        starts_at = Time.iso8601(values.fetch("starts_at"))
        ends_at = Time.iso8601(values.fetch("ends_at"))
        raise Unavailable, "The rights window is invalid." unless ends_at > starts_at && ends_at.future?

        previous = ProgramLicense.find_by(federation_key: key, publisher_peer: peer)
        if previous
          unless previous.licensee_site_id == target.id && previous.title == values.fetch("title") &&
              previous.creative_digest == values.fetch("sha256") && previous.starts_at == starts_at && previous.ends_at == ends_at
            raise Unavailable, "The uploaded program differs from the existing license."
          end
          return previous
        end

        Tempfile.create(["lightek-program-", ".mp4"]) do |file|
          file.binmode
          actual = IO.copy_stream(input, file, MAX_BYTES + 1)
          file.flush
          unless actual == length && actual.between?(1, MAX_BYTES) && Digest::SHA256.file(file.path).hexdigest == values.fetch("sha256")
            raise Unavailable, "The program file failed its integrity check."
          end
          ProgramLicense.transaction do
            asset = import_video!(file, site: peer.site, owner: peer.merchant)
            ProgramLicense.create!(licensor_site: peer.site, licensee_site: target, asset: asset, blob_id: asset.proxy.blob.id,
              title: values.fetch("title"), starts_at: starts_at, ends_at: ends_at, federation_key: key,
              publisher_peer: peer, creative_digest: values.fetch("sha256"))
          end
        end
      rescue JSON::ParserError, ArgumentError, KeyError, TypeError
        raise Unavailable, "The program exchange metadata is invalid."
      end

      def import!(site, key)
        Tempfile.create(["lightek-license-", ".mp4"]) do |file|
          file.binmode
          metadata = client(site).broadcast_media("broadcast/programs/#{key}/media", download: file)
          file.flush
          unless metadata.fetch("key") == key && metadata.fetch("status").in?(%w[offered accepted]) &&
              Digest::SHA256.file(file.path).hexdigest == metadata.fetch("sha256")
            raise Unavailable, "The received program failed its integrity check."
          end

          # Bind acceptance to the exact offered license before storing the copy.
          client(site).request("broadcast/programs/#{key}/accept", method: :post, body: {})
          site.with_lock do
            existing = ProgramLicense.find_by(federation_key: key, licensee_site: site)
            return existing if existing
            asset = import_video!(file, site: site, owner: site.tenant)
            ProgramLicense.create!(licensee_site: site, asset: asset, blob_id: asset.proxy.blob.id, title: metadata.fetch("title"),
              originator_name: metadata.fetch("source"), starts_at: Time.iso8601(metadata.fetch("starts_at")),
              ends_at: Time.iso8601(metadata.fetch("ends_at")), federation_key: key, status: "accepted")
          end
        end
      end

      def check_booking!(license)
        return unless license.imported?
        data = client(license.licensee_site).request("broadcast/programs/#{license.federation_key}/status")
        raise Unavailable, "The originating station has closed this license to future bookings." unless data["status"] == "accepted"
      end

      def import_video!(file, site:, owner:)
        raise Unavailable, "The station needs a business owner." unless owner.is_a?(::User)

        probe = Studio::MediaProcess.run!([ENV.fetch("LIGHTEK_FFPROBE", "ffprobe"), "-v", "error", "-protocol_whitelist", "file",
          "-format_whitelist", "mov,mp4,m4a,3gp,3g2,mj2", "-show_entries", "format=duration:stream=codec_type", "-of", "json", file.path], timeout: 25)
        media = JSON.parse(probe)
        types = media.fetch("streams").pluck("codec_type")
        duration = Float(media.fetch("format").fetch("duration"))
        raise Unavailable, "Choose an MP4 program between 2 seconds and 2 hours." unless duration.between?(2, 2.hours.to_i) && types.include?("video")

        asset = StudioAsset.create!(site: site, owner: owner, request_key: SecureRandom.uuid, name: "Licensed broadcast program",
          kind: "video", status: "ready", metadata: { "duration" => duration, "has_audio" => types.include?("audio"), "broadcast_program_exchange" => "reserved" })
        file.rewind
        asset.proxy.attach(io: file, filename: "licensed-program.mp4", content_type: "video/mp4", identify: false)
        asset
      rescue JSON::ParserError, KeyError, ArgumentError, RuntimeError, Timeout::Error
        raise Unavailable, "The program video could not be read."
      end
    end
  end
end
