module LightekMail
  class ContactPreview < ApplicationRecord
    self.table_name = "lightek_mail_contact_previews"

    belongs_to :account, class_name: "LightekMail::Account"
    belongs_to :team_mailbox, class_name: "LightekMail::TeamMigrationMailbox", optional: true

    scope :available, -> { where("expires_at > ?", Time.current) }
  end
end
