module LightekMail
  class CalendarHistoryEvent < ApplicationRecord
    self.table_name = "lightek_mail_calendar_history_events"

    belongs_to :account, class_name: "LightekMail::Account"

    scope :for_mailbox, ->(account) { where(account_id: account.id) }
  end
end
