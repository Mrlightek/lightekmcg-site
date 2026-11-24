# frozen_string_literal: true

require "base64"
require "digest"

module ItServices
  class RemoteSupportFiles
    Conflict = RemoteScreenShare::Conflict
    Denied = Gatekeeper::ItRemoteSupportPolicy::Denied
    MAX_FILES = 6
    MAX_BYTES = 1.megabyte
    TYPES = { ".txt" => "text/plain", ".log" => "text/plain", ".png" => "image/png",
      ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg" }.freeze

    def self.offer!(room, login, upload)
      raise Conflict, "File scanning is unavailable." unless RemoteSupportFileScanner.port

      RemoteScreenShare.with_live_room(room, login) do |work, _role|
        raise Conflict, "The session file limit has been reached." if room.transfers.count >= MAX_FILES
        unless upload.is_a?(ActionDispatch::Http::UploadedFile) && upload.size.between?(1, MAX_BYTES)
          raise Conflict, "Choose a file up to 1 MB."
        end

        filename = upload.original_filename.to_s
        unless filename.ascii_only? && filename.match?(/\A[A-Za-z0-9][A-Za-z0-9 _.-]{0,94}\.[A-Za-z]{2,4}\z/) && !filename.include?("..")
          raise Conflict, "Choose a file with a simple filename."
        end

        bytes = upload.read(MAX_BYTES + 1)
        media_type = TYPES[File.extname(filename).downcase]
        unless bytes&.bytesize&.between?(1, MAX_BYTES) && matches_type?(bytes, media_type)
          raise Conflict, "Choose a plain text, log, PNG, or JPEG file."
        end

        transfer = room.transfers.build(sender: login.user, filename: filename, media_type: media_type,
          byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes), state: "scanning")
        transfer.payload = encryptor.encrypt_and_sign(Base64.strict_encode64(bytes), purpose: purpose(transfer), expires_at: room.expires_at)
        transfer.save!
        audit!(work, room, transfer, login.user, "offered")
        transfer
      end
    end

    def self.scan!(transfer)
      return unless transfer.state == "scanning"

      room = transfer.it_remote_support_session
      verdict = scan_payload(transfer)
      room.it_service_request.with_lock do
        room.with_lock do
          transfer.reload
          next unless transfer.state == "scanning"

          if room.state != "approved" || room.expires_at.past?
            transfer.update!(state: "cancelled", payload: nil)
          elsif verdict == "awaiting_acceptance"
            transfer.update!(state: verdict)
          else
            transfer.update!(state: verdict, payload: nil)
          end
          audit!(room.it_service_request, room, transfer, transfer.sender, transfer.state)
        end
      end
    end

    def self.accept!(room, login, id)
      RemoteScreenShare.with_live_room(room, login) do |work, _role|
        transfer = room.transfers.find(id)
        raise Denied unless transfer.recipient?(login.user)
        raise Conflict, "This file is awaiting a clean scan." unless transfer.state == "awaiting_acceptance"

        transfer.update!(state: "accepted")
        audit!(work, room, transfer, login.user, "accepted")
      end
    end

    def self.cancel!(room, login, id)
      RemoteScreenShare.with_live_room(room, login) do |work, _role|
        transfer = room.transfers.pending.find(id)
        transfer.update!(state: "cancelled", payload: nil)
        audit!(work, room, transfer, login.user, "cancelled")
      end
    end

    def self.download!(room, login, id)
      RemoteScreenShare.with_live_room(room, login) do |work, _role|
        transfer = room.transfers.find(id)
        raise Denied unless transfer.recipient?(login.user) && transfer.state == "accepted"

        bytes = payload(transfer)
        raise Conflict, "File integrity could not be verified." unless bytes

        transfer.update!(state: "downloaded", payload: nil)
        audit!(work, room, transfer, login.user, "downloaded")
        { bytes: bytes, filename: transfer.filename, sha256: transfer.sha256 }
      end
    end

    def self.cancel_pending!(room, work, actor)
      room.transfers.pending.find_each do |transfer|
        transfer.update!(state: "cancelled", payload: nil)
        audit!(work, room, transfer, actor, "cancelled when session ended")
      end
    end

    def self.matches_type?(bytes, media_type)
      case media_type
      when "text/plain"
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        text.valid_encoding? && !text.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
      when "image/png"
        bytes.b.start_with?("\x89PNG\r\n\x1a\n".b)
      when "image/jpeg"
        bytes.b.start_with?("\xff\xd8\xff".b)
      else
        false
      end
    end
    private_class_method :matches_type?

    def self.scan_payload(transfer)
      bytes = payload(transfer)
      return "scan_failed" unless bytes

      RemoteSupportFileScanner.clean?(bytes) ? "awaiting_acceptance" : "quarantined"
    rescue RemoteSupportFileScanner::Unavailable
      "scan_failed"
    end
    private_class_method :scan_payload

    def self.payload(transfer)
      return unless transfer.payload

      encoded = encryptor.decrypt_and_verify(transfer.payload, purpose: purpose(transfer))
      return unless encoded.is_a?(String)

      bytes = Base64.strict_decode64(encoded)
      bytes if bytes.bytesize == transfer.byte_size &&
        ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(bytes), transfer.sha256)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError
      nil
    end
    private_class_method :payload

    def self.purpose(transfer)
      [transfer.it_remote_support_session_id, transfer.sender_id, transfer.filename, transfer.sha256].join(":")
    end
    private_class_method :purpose

    def self.encryptor
      @encryptor ||= begin
        cipher = "aes-256-gcm"
        key = Rails.application.key_generator.generate_key("it-remote-support-files-v1", ActiveSupport::MessageEncryptor.key_len(cipher))
        ActiveSupport::MessageEncryptor.new(key, cipher: cipher, serializer: :json)
      end
    end
    private_class_method :encryptor

    def self.audit!(work, room, transfer, actor, action)
      ItServiceEvent.create!(it_service_request: work, actor: actor, from_status: work.status, to_status: work.status,
        note: "Screen sharing ##{room.id}: file transfer ##{transfer.id} #{action}.")
    end
    private_class_method :audit!
  end
end
