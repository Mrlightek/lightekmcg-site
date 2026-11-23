class AddCalendarHistoryImports < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_mail_calendar_history_events do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.string :uid, null: false, limit: 255
      t.string :occurrence_key, null: false, default: "", limit: 32
      t.string :title, null: false, limit: 160
      t.string :location, limit: 300
      t.text :description
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.boolean :all_day, null: false, default: false
      t.boolean :cancelled, null: false, default: false
      t.string :zone
      t.string :rule
      t.jsonb :added_dates, null: false, default: []
      t.jsonb :excluded_dates, null: false, default: []
      t.timestamps
      t.index %i[account_id uid occurrence_key], unique: true, name: "idx_mail_history_event_identity"
      t.index %i[account_id starts_at], name: "idx_mail_history_calendar_dates"
    end
    create_table :lightek_mail_calendar_history_previews do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :team_mailbox, foreign_key: {to_table: :lightek_team_mail_migration_mailboxes}
      t.jsonb :events, null: false, default: []
      t.jsonb :issues, null: false, default: []
      t.datetime :expires_at, null: false
      t.timestamps
      t.index :expires_at
    end
    add_column :lightek_team_mail_migration_mailboxes, :calendar_imported_at, :datetime
  end
end
