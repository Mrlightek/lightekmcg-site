module LightekMail
  class DeliverJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true
    # No automatic SMTP retries: a disconnect after DATA may already mean accepted.
    def perform(id)
      smtp_attempted = false
      message = Message.find(id)
      account = message.account
      allowed = SendingPolicy.synchronize do |policy|
        account.with_lock do
          message.reload
          next false unless message.state == "queued"
          next false unless policy.sending_enabled?
          begin
            Access.authorize!(account.user)
          rescue Access::Denied
            message.update!(state: "failed", error_message: "Mail access was revoked before submission.")
            next false
          end
          unless account.sending_ready?
            message.update!(state: "failed", error_message: "Sending paused or domain verification removed.")
            next false
          end
          message.update!(state: "submitting")
          true
        end
      end
      return unless allowed
      delivery = MessageMailer.outbound(message, auto_reply: message.idempotency_key.to_s.start_with?("auto_"))
      SpamScanner.check!(delivery.message)
      # Recheck after scanning: a customer suspension or server stop may have arrived.
      ready = SendingPolicy.synchronize do |policy|
        account.with_lock do
          begin
            Access.authorize!(account.user.reload)
          rescue Access::Denied
            message.update!(state: "failed", error_message: "Mail access was revoked before SMTP submission.")
            next false
          end
          if policy.sending_enabled? && account.sending_ready?
            SendingLimits.dispatch!(account, message)
            true
          else
            message.update!(state: "failed", error_message: "Sending was paused before SMTP submission.")
            false
          end
        end
      end
      return unless ready
      smtp_attempted = true
      delivery.deliver_now
      message.update!(state: "sent", submitted_at: Time.current, error_message: nil)
    rescue SpamScanner::Rejected
      message.update!(state: "failed", error_message: "Outbound spam check blocked this message; administrator review required.")
      Feedback.record!(message_id: message.id, kind: "spam", event_key: "outbound_spam_#{message.id}")
    rescue SpamScanner::Unavailable
      message.update!(state: "queued", error_message: "Spam scanner unavailable; delivery deferred safely.")
      self.class.set(wait: 5.minutes).perform_later(id)
    rescue SendingLimits::Throttled
      message.update!(state: "queued", error_message: "Waiting for an SMTP recipient sending allowance.")
      self.class.set(wait: 61.seconds).perform_later(id)
    rescue StandardError => error
      if message&.persisted? && message.state == "submitting"
        state, detail = if smtp_attempted
          ["uncertain", "SMTP acceptance could not be confirmed. Check the mail queue before sending again."]
        else
          ["failed", "Submission stopped before SMTP. Contact the mail administrator."]
        end
        message.update_columns(state: state, error_message: detail, updated_at: Time.current)
      end
      Rails.logger.error("[LightekMail] submission stopped message_id=#{id} error_class=#{error.class.name}")
    end
  end
end
