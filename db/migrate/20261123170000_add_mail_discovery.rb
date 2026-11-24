class AddMailDiscovery < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_mail_retention_rules do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}, index: {unique: true}
      t.integer :days, null: false
      t.timestamps
      t.check_constraint "days BETWEEN 1 AND 36500", name: "mail_retention_days"
    end

    create_table :lightek_mail_matters do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}
      t.string :name, limit: 100, null: false
      t.timestamps
    end

    create_table :lightek_mail_matter_reviewers do |t|
      t.references :matter, null: false, foreign_key: {to_table: :lightek_mail_matters}, index: false
      t.references :user, null: false, foreign_key: true
      t.index %i[matter_id user_id], unique: true
    end

    create_table :lightek_mail_matter_holds do |t|
      t.references :matter, null: false, foreign_key: {to_table: :lightek_mail_matters}, index: false
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}
      t.datetime :released_at
      t.timestamps
      t.index %i[matter_id account_id], unique: true
    end

    create_table :lightek_mail_retained_messages do |t|
      t.references :account, null: false, foreign_key: {to_table: :lightek_mail_accounts}, index: false
      t.bigint :original_id, null: false
      t.datetime :sent_or_received_at, null: false
      t.string :subject, null: false
      t.string :from_address, null: false
      t.text :text_body
      t.json :snapshot, null: false
      t.timestamps
      t.index :original_id, unique: true
      t.index %i[account_id sent_or_received_at], name: "idx_mail_retained_by_date"
    end

    create_table :lightek_mail_discovery_events do |t|
      t.references :employer, null: false, foreign_key: {to_table: :users}, index: false
      t.references :matter, foreign_key: {to_table: :lightek_mail_matters}
      t.references :account, foreign_key: {to_table: :lightek_mail_accounts}
      t.references :actor, foreign_key: {to_table: :users}
      t.string :action, null: false
      t.json :details, null: false, default: {}
      t.integer :result_count
      t.datetime :created_at, null: false
      t.index %i[employer_id created_at], name: "idx_mail_discovery_activity"
    end
  end
end
