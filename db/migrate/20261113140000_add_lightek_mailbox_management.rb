class AddLightekMailboxManagement < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_mail_accounts, :mailbox_kind, :string, null: false, default: "mailbox"
    add_column :lightek_mail_accounts, :deleted_at, :datetime
    add_column :lightek_mail_accounts, :original_address, :string
    add_column :lightek_mail_accounts, :spam_filter_level, :string, null: false, default: "standard"
    add_column :lightek_mail_accounts, :allowed_senders, :json, null: false, default: []
    add_column :lightek_mail_accounts, :blocked_senders, :json, null: false, default: []
    add_column :lightek_mail_messages, :junk, :boolean, null: false, default: false
    add_column :lightek_mail_messages, :spam_score, :float
    add_column :lightek_mail_messages, :spam_reason, :string
    add_column :lightek_mail_messages, :spam_scanned_at, :datetime
    change_column_default :lightek_mail_accounts, :enabled, from: false, to: true
    change_column_default :lightek_mail_sending_policies, :sending_enabled, from: false, to: true
    add_column :lightek_mail_envelopes, :recipient_snapshots, :json, null: false, default: {}
    create_table :lightek_mail_group_members do |t|
      t.references :group, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :member, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.timestamps
    end
    add_index :lightek_mail_group_members, [:group_id, :member_id], unique: true, name: "idx_mail_group_members_unique"
    reversible do |direction|
      direction.up do
        # A documented operator/abuse stop stays in force. Only the old
        # unexplained bootstrap pause is removed for the automatic workflow.
        execute "UPDATE lightek_mail_sending_policies SET sending_enabled = TRUE WHERE sending_enabled = FALSE AND (stop_reason IS NULL OR stop_reason = '')"
      end
    end
  end
end
