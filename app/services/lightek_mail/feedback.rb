module LightekMail
  class Feedback
    # Only authenticated operational feedback belongs here, never arbitrary inbound DSNs.
    def self.record!(message_id:, kind:, event_key:)
      raise ArgumentError, "Unknown feedback type." unless kind.in?(%w[hard_bounce complaint spam])
      SendingPolicy.synchronize do |policy|
        existing = FeedbackEvent.find_by(event_key: event_key)
        if existing
          raise ArgumentError, "Feedback key already refers to another event." unless existing.message_id == message_id.to_i && existing.kind == kind
          next existing
        end
        message = Message.where(direction: "outbound").find(message_id)
        account = message.account
        account.with_lock do
          event = FeedbackEvent.create!(account: account, message_id: message.id, kind: kind, event_key: event_key)
          recent = FeedbackEvent.joins(:account).where(lightek_mail_accounts: {user_id: account.user_id}).where("lightek_mail_feedback_events.created_at > ?", 1.day.ago)
          attempts = SendReservation.where(user_id: account.user_id).where("reserved_at > ?", 1.day.ago).sum(:recipient_count)
          # Count bounced messages, not repeated reports for one message.
          bounces = recent.where(kind: "hard_bounce").distinct.count(:message_id)
          if kind.in?(%w[complaint spam]) || (attempts >= 20 && bounces >= 5 && bounces.fdiv(attempts) >= 0.1)
            CustomerSuspension.find_or_create_by!(user_id: account.user_id) { |suspension| suspension.reason = "Outbound abuse feedback requires administrator review." }
            Account.where(user_id: account.user_id).update_all(suspended_at: Time.current, suspension_reason: "Outbound abuse feedback requires administrator review.", updated_at: Time.current)
          end
          if FeedbackEvent.where(kind: "complaint").where("created_at > ?", 1.hour.ago).distinct.count(:message_id) >= 3
            policy.update!(sending_enabled: false, stop_reason: "Complaint threshold reached; investigate before resuming.")
          end
          event
        end
      end
    end
  end
end
