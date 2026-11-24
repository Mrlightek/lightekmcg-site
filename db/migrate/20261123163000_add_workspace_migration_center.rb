class AddWorkspaceMigrationCenter < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_team_mail_migrations, :pilot, :boolean, null: false, default: false
    add_column :lightek_team_mail_migrations, :pilot_verified_at, :datetime
    add_column :lightek_team_mail_migration_mailboxes, :contacts_import_result, :jsonb, null: false, default: {}
    add_column :lightek_team_mail_migration_mailboxes, :calendar_import_result, :jsonb, null: false, default: {}
    add_reference :lightek_shared_drive_imports, :team_migration,
      foreign_key: {to_table: :lightek_team_mail_migrations}
  end
end
