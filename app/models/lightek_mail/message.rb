module LightekMail
  class Message < ApplicationRecord
    self.table_name = "lightek_mail_messages"
    belongs_to :account, class_name: "LightekMail::Account"
    has_many_attached :attachments
    has_one_attached :source
    validates :direction, inclusion: {in: %w[inbound outbound]}
    validates :state, inclusion: {in: %w[inbox draft queued submitting sent failed uncertain]}
    validates :subject, length: {maximum: 200}, format: {without: /[\r\n]/}
    validates :message_id, presence: true
    scope :visible, -> { where(trashed: false) }
  end
end
