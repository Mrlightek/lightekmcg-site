module LightekMail
  class RetainedMessage < ApplicationRecord
    self.table_name = "lightek_mail_retained_messages"

    SNAPSHOT_FIELDS = %w[message_id in_reply_to direction state to_addresses cc_addresses bcc_addresses html_body submitted_at].freeze

    belongs_to :account, class_name: "LightekMail::Account"
    has_many_attached :attachments
    has_one_attached :source

    def self.preserve!(message)
      create!(account_id: message.account_id, original_id: message.id, subject: message.subject,
        from_address: message.from_address, text_body: message.text_body, sent_or_received_at: message.discovery_date,
        snapshot: message.attributes.slice(*SNAPSHOT_FIELDS),
        attachments: message.attachments.map(&:blob), source: message.source.blob)
    end
  end
end
