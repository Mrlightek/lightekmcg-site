class AddMailContacts < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_mail_contacts do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.string :name, null: false, limit: 200
      t.string :import_key, null: false, limit: 64
      t.jsonb :source_emails, null: false, default: []
      t.jsonb :emails, null: false, default: []
      t.jsonb :phones, null: false, default: []
      t.jsonb :labels, null: false, default: []
      t.timestamps
      t.index [:account_id, :import_key], unique: true, name: "idx_mail_contact_import_identity"
    end
    create_table :lightek_mail_contact_previews do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :team_mailbox, foreign_key: {to_table: :lightek_team_mail_migration_mailboxes}
      t.jsonb :contacts, null: false, default: []
      t.integer :invalid_rows, null: false, default: 0
      t.datetime :expires_at, null: false
      t.timestamps
      t.index :expires_at
    end
    add_column :lightek_team_mail_migration_mailboxes, :contacts_imported_at, :datetime
  end
end
