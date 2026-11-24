module LightekWorkspace
  class ExternalInvitation < ApplicationRecord
    self.table_name = 'lightek_shared_external_invitations'
    MESSAGE_PREFIX = 'shared_calendar_'.freeze

    belongs_to :event, class_name: 'LightekWorkspace::Event'
    belongs_to :mailbox, class_name: 'LightekMail::Account'
    belongs_to :message, class_name: 'LightekMail::Message', optional: true

    def self.current_message?(message, mailbox)
      exists?(message_id: message.id, mailbox_id: mailbox.id, organizer_address: mailbox.address)
    end

    def enqueue_delivery
      ExternalInvitationJob.perform_later(id, sequence)
    end

    def revise!
      update!(sequence: sequence + 1, response: 'pending', reply_timestamp: nil, message: nil, delivery_error: nil)
      enqueue_delivery
    end
  end
end
