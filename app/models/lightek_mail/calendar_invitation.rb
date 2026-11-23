module LightekMail
  class CalendarInvitation < ApplicationRecord
    self.table_name = "lightek_mail_calendar_invitations"

    belongs_to :account, class_name: "LightekMail::Account"
    belongs_to :source_message, class_name: "LightekMail::Message", optional: true
    belongs_to :reply_message, class_name: "LightekMail::Message", optional: true

    scope :for_mailbox, ->(account) { where(account_id: account.id, attendee: account.address) }

    def self.for_notice(account, notice)
      for_mailbox(account).find_by(uid: notice.fetch("uid"), organizer: notice.fetch("organizer"))
    end

    def version
      [sequence, stamp]
    end
  end
end
