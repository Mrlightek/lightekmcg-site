# frozen_string_literal: true

module ItServices
  class RemoteScreenShare
    Policy = Gatekeeper::ItRemoteSupportPolicy
    class Conflict < StandardError; end
    REQUEST_TTL = 5.minutes
    SESSION_TTL = 30.minutes
    SDP_LIMIT = 24.kilobytes

    def self.request!(work, login)
      work.with_lock do
        role = Policy.participant!(login: login, customer_id: work.user_id, technician_id: work.technician_id)
        raise Policy::Denied unless role == :technician
        Policy.case_active!(work, customer_id: work.user_id, technician_id: work.technician_id)
        room = ItRemoteSupportSession.create!(it_service_request: work, customer_id: work.user_id,
          technician_id: work.technician_id, technician_session_id: login.id, expires_at: REQUEST_TTL.from_now)
        audit!(room, work, login.user, "requested")
        DymondDash::Notification.create!(recipient: work.user, subject: room, category: "system",
          title: "Screen-sharing request", body: "Your assigned technician has requested screen viewing for IT Service Request ##{work.id}.",
          url: Rails.application.routes.url_helpers.dashboard_remote_support_session_path(room))
        room
      end
    rescue ActiveRecord::RecordNotUnique
      raise Conflict, "A screen-sharing request is already open for one of the participants."
    end

    def self.approve!(room, login)
      with_authorization(room, login) do |work, role|
        raise Policy::Denied unless role == :customer
        raise Conflict, "This request is no longer open." unless room.state == "requested" && room.expires_at.future?
        Policy.technician_login!(room)
        room.update!(state: "approved", consented_at: Time.current, expires_at: SESSION_TTL.from_now,
          customer_session_id: login.id)
        audit!(room, work, login.user, "customer approved screen viewing")
      end
    end

    def self.exchange!(room, login, sdp, display_reported: false)
      with_live_room(room, login) do |work, role|
        if sdp
          media = sdp.is_a?(String) && sdp.bytesize <= SDP_LIMIT && sdp.lines.grep(/\Am=/)
          direction = role == :customer ? "a=sendonly" : "a=recvonly"
          unless media && media.size == 1 && media.first.start_with?("m=video ") && sdp.lines.map(&:strip).grep(/\Aa=(?:sendonly|recvonly|sendrecv|inactive)\z/) == [direction]
            raise Conflict, "A single screen video track is required."
          end
          column = role == :customer ? :offer_sdp : :answer_sdp
          raise Conflict, "This connection has already been negotiated." if room[column].present?
          raise Conflict, "The customer has not shared a screen yet." if role == :technician && room.offer_sdp.blank?
          room.update!(column => encryptor.encrypt_and_sign(sdp, purpose: "#{room.id}:#{column}", expires_at: room.expires_at))
          audit!(room, work, login.user, role == :customer ? "customer sent screen offer" : "technician answered screen offer")
        end
        if display_reported && role == :technician && room.answer_sdp.present? && room.display_reported_at.nil?
          room.update!(display_reported_at: Time.current)
          audit!(room, work, login.user, "technician browser reported video displayed")
        end
        peer_column = role == :customer ? :answer_sdp : :offer_sdp
        encrypted = room[peer_column]
        { sdp: encrypted && encryptor.decrypt_and_verify(encrypted, purpose: "#{room.id}:#{peer_column}"),
          recording: RemoteSupportRecordings.status(room), display_reported: room.display_reported_at.present?, valid_for_ms: [(room.expires_at - Time.current) * 1000, 0].max.floor }
      end
    end

    def self.with_live_room(room, login)
      with_authorization(room, login) do |work, role|
        Policy.live!(room, login, role)
        yield work, role
      end
    end

    def self.end!(room, login)
      with_authorization(room, login, require_active: false) do |work, role|
        reason = if role == :customer
          room.state == "requested" ? "declined" : "customer revoked access"
        else
          "technician ended session"
        end
        close!(room, work, login.user, reason)
      end
    end

    def self.expire!(room)
      work = room.it_service_request
      work.with_lock do
        room.with_lock do
          close!(room, work, room.customer, "authorization expired") if room.expires_at <= Time.current
        end
      end
    end

    def self.with_authorization(room, login, require_active: true)
      work = room.it_service_request
      raise Policy::Denied unless work

      work.with_lock do
        room.with_lock do
          role = Policy.participant!(login: login, customer_id: room.customer_id, technician_id: room.technician_id)
          if require_active
            Policy.case_active!(work, customer_id: room.customer_id, technician_id: room.technician_id)
            Policy.browser_bound!(room, login, role)
          end
          yield work, role
        end
      end
    end
    private_class_method :with_authorization

    def self.encryptor
      @encryptor ||= begin
        cipher = "aes-256-gcm"
        key = Rails.application.key_generator.generate_key("it-remote-support-sdp-v1", ActiveSupport::MessageEncryptor.key_len(cipher))
        ActiveSupport::MessageEncryptor.new(key, cipher: cipher)
      end
    end
    private_class_method :encryptor

    def self.close!(room, work, actor, reason)
      return if room.state == "ended"

      room.update!(state: "ended", ended_at: Time.current, end_reason: reason, offer_sdp: nil, answer_sdp: nil)
      RemoteSupportFiles.cancel_pending!(room, work, actor)
      audit!(room, work, actor, reason)
      ActiveRecord.after_all_transactions_commit do
        begin
          ItRemoteSupportCaseReceiptJob.perform_later(room.id, actor.id)
        rescue StandardError => error
          Rails.logger.warn("Remote support case receipt enqueue failed session_id=#{room.id}: #{error.class}")
        end
      end
    end
    private_class_method :close!

    def self.audit!(room, work, actor, event)
      ItServiceEvent.create!(it_service_request: work, actor: actor, from_status: work.status,
        to_status: work.status, note: "Screen sharing ##{room.id}: #{event}.")
    end
    private_class_method :audit!
  end
end
