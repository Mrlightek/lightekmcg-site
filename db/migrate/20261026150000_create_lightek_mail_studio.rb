class CreateLightekMailStudio < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_mail_domains do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :verification_token, null: false
      t.datetime :verified_at
      t.timestamps
    end
    add_index :lightek_mail_domains, :name, unique: true
    create_table :lightek_mail_accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :domain, null: false, foreign_key: {to_table: :lightek_mail_domains}
      t.string :address, null: false
      t.string :display_name, null: false
      t.boolean :enabled, null: false, default: false
      t.integer :daily_limit, null: false, default: 200
      t.date :send_day
      t.integer :send_count, null: false, default: 0
      t.bigint :storage_limit, null: false, default: 1_073_741_824
      t.string :token_digest
      t.string :token_hint
      t.boolean :auto_reply_enabled, null: false, default: false
      t.bigint :auto_template_id
      t.timestamps
    end
    add_index :lightek_mail_accounts, :address, unique: true
    add_index :lightek_mail_accounts, :token_digest, unique: true
    create_table :lightek_mail_templates do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.string :name, null: false
      t.string :subject, null: false
      t.json :document, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :lightek_mail_accounts, :lightek_mail_templates, column: :auto_template_id
    create_table :lightek_mail_messages do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.string :direction, null: false
      t.string :state, null: false
      t.string :from_address, null: false
      t.json :to_addresses, null: false, default: []
      t.json :cc_addresses, null: false, default: []
      t.json :bcc_addresses, null: false, default: []
      t.string :subject, null: false, default: ""
      t.text :text_body
      t.text :html_body
      t.string :message_id, null: false
      t.string :in_reply_to
      t.string :idempotency_key
      t.string :error_message
      t.boolean :starred, null: false, default: false
      t.boolean :archived, null: false, default: false
      t.boolean :trashed, null: false, default: false
      t.datetime :read_at
      t.datetime :submitted_at
      t.bigint :bytesize, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_mail_messages, [:account_id, :idempotency_key], unique: true, name: "idx_mail_idempotency"
    add_index :lightek_mail_messages, [:account_id, :created_at], name: "idx_mail_recent"
    create_table :lightek_mail_auto_replies do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.string :sender, null: false
      t.date :day, null: false
      t.timestamps
    end
    add_index :lightek_mail_auto_replies, [:account_id, :sender, :day], unique: true, name: "idx_mail_auto_once"
    create_table :lightek_mail_envelopes do |t|
      t.bigint :inbound_email_id, null: false
      t.json :recipients, null: false, default: []
      t.timestamps
    end
    add_index :lightek_mail_envelopes, :inbound_email_id, unique: true
    add_foreign_key :lightek_mail_envelopes, :action_mailbox_inbound_emails, column: :inbound_email_id, on_delete: :cascade
  end
end
