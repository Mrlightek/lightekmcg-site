module LightekWorkspace
  class ExternalInvitationJob < ApplicationJob
    queue_as :default
    self.enqueue_after_transaction_commit = true

    retry_on LightekMail::SendingLimits::Throttled, wait: 65.seconds, attempts: 5 do |job, error|
      invitation_id, sequence = job.arguments
      ExternalInvitation.where(id: invitation_id, sequence: sequence, message_id: nil)
        .update_all(delivery_error: error.message, updated_at: Time.current)
    end

    def perform(id, sequence)
      invitation = ExternalInvitation.find_by(id: id)
      return unless invitation

      invitation.event.with_lock do
        invitation.reload
        next if invitation.sequence != sequence || invitation.message_id?

        begin
          mailbox = LightekMail::Account.mailboxes.find(invitation.mailbox_id)
          LightekMail::Access.authorize!(mailbox.user)
          unless mailbox.sending_ready? && mailbox.address == invitation.organizer_address
            raise LightekMail::Submission::Unavailable, 'The original organizer mailbox is unavailable.'
          end

          invitation.update!(message: CalendarInvitationMail.submit!(invitation, mailbox), delivery_error: nil)
        rescue LightekMail::SendingLimits::Throttled
          raise
        rescue LightekMail::Submission::Unavailable,
               LightekMail::Access::Denied, ActiveRecord::RecordNotFound, ArgumentError => error
          invitation.update!(delivery_error: error.message.to_s.slice(0, 255))
        end
      end
    end
  end
end
