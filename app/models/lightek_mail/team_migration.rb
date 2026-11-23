module LightekMail
  class TeamMigration < ApplicationRecord
    self.table_name = "lightek_team_mail_migrations"

    belongs_to :employer, class_name: "User"
    has_many :mailboxes, class_name: "LightekMail::TeamMigrationMailbox", foreign_key: :migration_id, inverse_of: :migration

    validates :name, presence: true, length: {maximum: 100}

    def self.workspace_for!(actor)
      LightekPeople::Access.new(actor: actor, employer: actor).require!(:owner)
      LightekTeam::Workspace.new(actor: actor, employer: actor)
    end
  end
end
