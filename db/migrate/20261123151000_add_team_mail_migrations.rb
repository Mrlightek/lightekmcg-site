class AddTeamMailMigrations < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_team_mail_migrations do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false, limit: 100
      t.timestamps
    end

    create_table :lightek_team_mail_migration_mailboxes do |t|
      t.references :migration, null: false, index: false, foreign_key: {to_table: :lightek_team_mail_migrations}
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :mailbox_user, null: false, foreign_key: {to_table: :users}
      t.string :source_address, null: false, limit: 254
      t.string :destination_address, null: false, limit: 254
      t.timestamps

      t.index %i[migration_id source_address], unique: true, name: "idx_team_mail_source"
      t.index %i[migration_id account_id], unique: true, name: "idx_team_mail_destination"
    end

    add_reference :lightek_mail_imports, :team_mailbox, index: {unique: true},
      foreign_key: {to_table: :lightek_team_mail_migration_mailboxes}
    add_column :lightek_mail_imports, :approved_at, :datetime
  end
end
