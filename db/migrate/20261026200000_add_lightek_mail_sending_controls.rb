class AddLightekMailSendingControls < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_mail_accounts, :minute_limit, :integer, null: false, default: 5
    add_column :lightek_mail_accounts, :hour_limit, :integer, null: false, default: 25
    add_column :lightek_mail_accounts, :suspended_at, :datetime
    add_column :lightek_mail_accounts, :suspension_reason, :string
    change_column_default :lightek_mail_accounts, :daily_limit, from: 200, to: 100

    create_table :lightek_mail_sending_policies do |t|
      t.boolean :sending_enabled, null: false, default: false
      t.string :stop_reason
      t.timestamps
    end
    # A single row serializes reservations across workers and customer mailboxes.
    add_check_constraint :lightek_mail_sending_policies, "id = 1", name: "mail_single_sending_policy"

    create_table :lightek_mail_customer_suspensions do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.string :reason, null: false
      t.timestamps
    end

    create_table :lightek_mail_send_reservations do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :user, null: false, foreign_key: true
      t.bigint :message_id, null: false
      t.integer :recipient_count, null: false
      t.datetime :reserved_at, null: false
      t.datetime :dispatched_at
    end
    add_index :lightek_mail_send_reservations, :message_id, unique: true
    add_index :lightek_mail_send_reservations, :reserved_at
    add_index :lightek_mail_send_reservations, :dispatched_at
    add_index :lightek_mail_send_reservations, [:account_id, :reserved_at], name: "idx_mail_account_reservations"
    add_index :lightek_mail_send_reservations, [:user_id, :reserved_at], name: "idx_mail_customer_reservations"
    add_check_constraint :lightek_mail_send_reservations, "recipient_count > 0 AND recipient_count <= 20", name: "mail_recipient_count_range"

    create_table :lightek_mail_feedback_events do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.bigint :message_id, null: false
      t.string :event_key, null: false
      t.string :kind, null: false
      t.timestamps
    end
    add_index :lightek_mail_feedback_events, :event_key, unique: true
    add_index :lightek_mail_feedback_events, [:account_id, :created_at], name: "idx_mail_recent_feedback"
  end
end
