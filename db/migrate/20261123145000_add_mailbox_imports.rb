class AddMailboxImports < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_mail_messages, :imported_at, :datetime
    add_column :lightek_mail_messages, :imported_labels, :jsonb, null: false, default: []
    add_index :lightek_mail_messages, [:account_id, :message_id], name: "idx_mail_account_message_identity"

    create_table :lightek_mail_imports do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts, on_delete: :cascade}
      t.references :requested_by, null: false, foreign_key: {to_table: :users}
      t.string :mailbox_address, null: false
      t.string :state, null: false, default: "queued"
      t.string :phase, null: false, default: "preview"
      t.string :run_token, null: false
      t.bigint :archive_bytes, null: false
      t.bigint :byte_offset, null: false, default: 0
      t.jsonb :preview, null: false, default: {}
      t.jsonb :results, null: false, default: {}
      t.string :error_message
      t.timestamps
    end
  end
end
