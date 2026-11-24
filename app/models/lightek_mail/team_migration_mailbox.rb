module LightekMail
  class TeamMigrationMailbox < ApplicationRecord
    self.table_name = "lightek_team_mail_migration_mailboxes"

    belongs_to :migration, class_name: "LightekMail::TeamMigration", inverse_of: :mailboxes
    belongs_to :account, class_name: "LightekMail::Account"
    belongs_to :mailbox_user, class_name: "User"
    has_one :mailbox_import, class_name: "LightekMail::MailboxImport", foreign_key: :team_mailbox_id, inverse_of: :team_mailbox

    def authorize_upload!(actor, destination = account)
      unless actor.id == migration.employer_id && destination.id == account_id &&
          destination.user_id == mailbox_user_id && destination.address == destination_address
        raise Access::Denied, "The mapped mailbox changed or is unavailable."
      end

      workspace = TeamMigration.workspace_for!(actor)
      unless workspace.roster.exists?(mailbox_user_id) && Account.mailboxes.exists?(account_id)
        raise Access::Denied, "The mapped mailbox is unavailable in this workspace."
      end
    rescue LightekPeople::Access::Denied
      raise Access::Denied, "Only the active workspace owner can manage this migration."
    end

    def requires_approval?
      mailbox_user_id != migration.employer_id
    end
  end
end
