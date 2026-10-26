module LightekMail
  class SendingLimits
    class Throttled < Submission::Unavailable; end
    WINDOWS = {minute: 60, hour: 3600, day: 86_400}.freeze
    DEFAULTS = {customer: {minute: 10, hour: 50, day: 200}, server: {minute: 25, hour: 100, day: 500}}.freeze

    # Caller holds the policy lock, followed by the account lock, in that order.
    def self.reserve!(policy, account, message)
      raise Submission::Unavailable, "Server sending is paused by the mail administrator." unless policy.sending_enabled?
      raise Submission::Unavailable, "Mailbox sending is paused, suspended or unverified." unless account.sending_ready?
      count = (message.to_addresses + message.cc_addresses + message.bcc_addresses).uniq.size
      check!(account, count, timestamp: :reserved_at)
      now = Time.current
      SendReservation.create!(account: account, user_id: account.user_id, message_id: message.id, recipient_count: count, reserved_at: now)
      # Retain legacy counters for operational visibility; reservations enforce rolling limits.
      account.update!(send_day: Date.current, send_count: (account.send_day == Date.current ? account.send_count : 0) + count)
      message.update!(state: "queued")
    end

    def self.dispatch!(account, message)
      reservation = SendReservation.find_by!(message_id: message.id, account_id: account.id)
      raise Submission::Unavailable, "This message already reserved an SMTP dispatch." if reservation.dispatched_at
      check!(account, reservation.recipient_count, timestamp: :dispatched_at)
      reservation.update!(dispatched_at: Time.current)
    end

    def self.check!(account, count, timestamp:)
      now = Time.current
      recent = SendReservation.where("#{timestamp} > ?", now - 1.day)
      scopes = {mailbox: recent.where(account_id: account.id), customer: recent.where(user_id: account.user_id), server: recent}
      scopes.each do |scope, relation|
        WINDOWS.each do |window, seconds|
          limit = if scope == :mailbox
            account.public_send({minute: :minute_limit, hour: :hour_limit, day: :daily_limit}.fetch(window))
          else
            Integer(ENV.fetch("LIGHTEK_MAIL_#{scope.upcase}_#{window.upcase}_LIMIT", DEFAULTS.fetch(scope).fetch(window).to_s))
          end
          raise Submission::Unavailable, "Invalid mail sending policy; contact the mail administrator." unless limit.positive?
          used = relation.where("#{timestamp} > ?", now - seconds).sum(:recipient_count)
          raise Throttled, "#{scope.to_s.capitalize} #{window} recipient sending limit reached." if used + count > limit
        end
      end
    end
  end
end
