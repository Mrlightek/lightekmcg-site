# frozen_string_literal: true

require "base64"
require "json"
require "open3"
require "tempfile"

module ItServices
  class RemoteSupportRecordings
    Conflict = RemoteScreenShare::Conflict
    Policy = Gatekeeper::ItRemoteSupportPolicy
    MAX_BYTES = 5.megabytes
    MAX_DURATION = 60.seconds
    WEBM_HEADER = "\x1A\x45\xDF\xA3".b

    def self.consent!(room, login)
      RemoteScreenShare.with_live_room(room, login) do |work, role|
        recording = room.recording || room.build_recording
        raise Conflict, "Recording authorization was withdrawn." if recording.revoked_at?

        field = role == :customer ? :customer_consented_at : :technician_consented_at
        unless recording[field]
          recording.update!(field => Time.current)
          audit!(work, room, login.user, "#{role} opted into recording")
        end
        recording
      end
    end

    def self.start!(room, login)
      RemoteScreenShare.with_live_room(room, login) do |work, role|
        raise Policy::Denied unless role == :customer
        recording = room.recording
        raise Conflict, "Both participants must approve recording." unless recording&.consented?
        raise Conflict, "This session has already started a recording." if recording.started_at?
        raise Conflict, "Connect the technician browser first." unless room.display_reported_at?

        recording.update!(started_at: Time.current)
        audit!(work, room, login.user, "customer started recording")
      end
    end

    def self.store!(room, login, upload)
      RemoteScreenShare.with_live_room(room, login) do |_, role|
        require_upload_authorization!(room, role)
      end
      unless upload.is_a?(ActionDispatch::Http::UploadedFile) &&
          upload.content_type == "video/webm" && upload.size.between?(1, MAX_BYTES)
        raise Conflict, "Recording must be a WebM video up to 5 MB."
      end
      bytes = upload.read(MAX_BYTES + 1)
      unless bytes.bytesize.between?(1, MAX_BYTES) && bytes.b.start_with?(WEBM_HEADER) && video_only?(bytes)
        raise Conflict, "Recording must contain one WebM video track and no audio."
      end

      RemoteScreenShare.with_live_room(room, login) do |work, role|
        recording = require_upload_authorization!(room, role)
        expires_at = retention_days.days.from_now
        payload = encryptor.encrypt_and_sign(Base64.strict_encode64(bytes), purpose: recording.id.to_s, expires_at: expires_at)
        recording.update!(payload: payload, expires_at: expires_at)
        audit!(work, room, login.user, "recording stored")
        recording
      end
    end

    def self.revoke!(room, login)
      room.it_service_request.with_lock do
        room.with_lock do
          Policy.participant!(login: login, customer_id: room.customer_id, technician_id: room.technician_id)
          recording = room.recording || room.build_recording
          unless recording.revoked_at?
            recording.update!(revoked_at: Time.current, payload: nil)
            audit!(room.it_service_request, room, login.user, "recording permission withdrawn")
          end
        end
      end
    end

    def self.playback!(room, login)
      room.it_service_request.with_lock do
        room.with_lock do
          Policy.participant!(login: login, customer_id: room.customer_id, technician_id: room.technician_id)
          work = room.it_service_request
          raise Policy::Denied unless work.user_id == room.customer_id && work.technician_id == room.technician_id
          recording = room.recording
          raise Policy::Denied unless recording&.available?

          encoded = encryptor.decrypt_and_verify(recording.payload, purpose: recording.id.to_s)
          raise Policy::Denied unless encoded
          bytes = Base64.strict_decode64(encoded)
          audit!(work, room, login.user, "recording accessed")
          bytes
        end
      end
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
      raise Policy::Denied
    end

    def self.status(room)
      customer, technician, revoked, started, expires_at, stored = ItRemoteSupportRecording
        .where(it_remote_support_session_id: room.id)
        .pick(:customer_consented_at, :technician_consented_at, :revoked_at, :started_at, :expires_at,
          Arel.sql("payload IS NOT NULL"))
      {
        customer: customer.present?,
        technician: technician.present?,
        revoked: revoked.present?,
        started: started.present?,
        saved: stored && expires_at&.future? && revoked.nil?
      }
    end

    def self.require_upload_authorization!(room, role)
      raise Policy::Denied unless role == :customer

      recording = room.recording
      unless recording&.consented? && recording.started_at? && recording.expires_at.nil? &&
          recording.started_at >= (MAX_DURATION + 30.seconds).ago
        raise Conflict, "Recording authorization is unavailable."
      end
      recording
    end
    private_class_method :require_upload_authorization!

    def self.video_only?(bytes)
      Tempfile.create(["lightek-support-recording", ".webm"], binmode: true) do |file|
        file.write(bytes)
        file.flush
        result, status = Open3.capture2("/usr/bin/timeout", "--kill-after=1s", "5s", "/usr/bin/ffprobe",
          "-v", "error", "-max_alloc", "16777216", "-protocol_whitelist", "file", "-f", "matroska",
          "-show_entries", "stream=codec_name,codec_type,width,height:format=duration", "-of", "json", file.path)
        next false unless status.success?

        metadata = JSON.parse(result)
        streams = metadata.fetch("streams", [])
        video = streams.first
        duration = Float(metadata.dig("format", "duration"), exception: false)
        streams.one? && video["codec_type"] == "video" && video["codec_name"].in?(%w[vp8 vp9 av1]) &&
          video["width"].to_i.between?(1, 3840) && video["height"].to_i.between?(1, 2160) &&
          (duration.nil? || duration.between?(0, MAX_DURATION + 1))
      end
    rescue SystemCallError, JSON::ParserError
      false
    end
    private_class_method :video_only?

    def self.retention_days
      configured = Integer(Rails.application.credentials.dig(:it_remote_support, :recording_retention_days), exception: false)
      configured&.between?(1, 30) ? configured : 7
    end
    private_class_method :retention_days

    def self.encryptor
      @encryptor ||= begin
        cipher = "aes-256-gcm"
        key = Rails.application.key_generator.generate_key("it-remote-support-recording-v1", ActiveSupport::MessageEncryptor.key_len(cipher))
        ActiveSupport::MessageEncryptor.new(key, cipher: cipher, serializer: :json)
      end
    end
    private_class_method :encryptor

    def self.audit!(work, room, user, event)
      ItServiceEvent.create!(it_service_request: work, actor: user, from_status: work.status,
        to_status: work.status, note: "Screen sharing ##{room.id}: #{event}.")
    end
    private_class_method :audit!
  end
end
