module LightekMail
  class DeliverJob < ApplicationJob
    queue_as :default
    # No automatic SMTP retries: a disconnect after DATA may already mean accepted.
    def perform(id)
      message = Message.find(id)
      account = message.account
      allowed = account.with_lock do
        message.reload
        next false unless message.state == "queued"
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
      return unless allowed
      MessageMailer.outbound(message, auto_reply: message.idempotency_key.to_s.start_with?("auto_")).deliver_now
      message.update!(state: "sent", submitted_at: Time.current, error_message: nil)
    rescue StandardError => error
      if message&.persisted? && message.state == "submitting"
        message.update_columns(state: "uncertain", error_message: "SMTP acceptance could not be confirmed. Check the mail queue before sending again.", updated_at: Time.current)
      end
      Rails.logger.error("[LightekMail] submission stopped message_id=#{id} error_class=#{error.class.name}")
    end
  end
end
