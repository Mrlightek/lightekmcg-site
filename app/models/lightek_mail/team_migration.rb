module LightekMail
  class TeamMigration < ApplicationRecord
    self.table_name = "lightek_team_mail_migrations"

    belongs_to :employer, class_name: "User"
    has_many :mailboxes, class_name: "LightekMail::TeamMigrationMailbox", foreign_key: :migration_id, inverse_of: :migration

    has_many :drive_imports, class_name: "LightekWorkspace::DriveImport", inverse_of: :team_migration

    validates :name, presence: true, length: {maximum: 100}

    def pilot_in_progress?
      pilot? && !pilot_verified_at?
    end

    def pilot_ready?
      return false unless pilot_in_progress?

      mailbox = mailboxes.first
      return false unless mailbox&.mailbox_import&.state == "complete" && mailbox.contacts_imported_at? && mailbox.calendar_imported_at?

      drive_imports.where(state: "complete").any? do |import|
        import.items.any? { |item| item["type"] != "folder" && item["status"].in?(%w[imported duplicate]) }
      end
    end

    def verify_pilot!
      with_lock do
        raise ArgumentError, "Finish the pilot mailbox, contacts, calendar, and Shared Drive import before expanding." unless pilot_ready?

        update!(pilot_verified_at: Time.current)
      end
    end

    def self.workspace_for!(actor)
      LightekPeople::Access.new(actor: actor, employer: actor).require!(:owner)
      LightekTeam::Workspace.new(actor: actor, employer: actor)
    end
  end
end
