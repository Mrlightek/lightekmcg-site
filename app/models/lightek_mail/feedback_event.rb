module LightekMail
  class FeedbackEvent < ApplicationRecord
    self.table_name = "lightek_mail_feedback_events"
    belongs_to :account, class_name: "LightekMail::Account"
    validates :kind, inclusion: {in: %w[hard_bounce complaint spam]}
    validates :event_key, format: {with: /\A[a-zA-Z0-9_-]{8,100}\z/}
  end
end
