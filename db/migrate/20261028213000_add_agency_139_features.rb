class AddAgency139Features < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_marketing_contacts, :subscription_token_digest, :string
    add_column :lightek_marketing_contacts, :confirmation_sent_at, :datetime
    add_column :lightek_marketing_campaigns, :sequence_delay_hours, :integer, null: false, default: 0
    add_column :lightek_marketing_campaigns, :scheduled_at, :datetime
    add_column :lightek_marketing_campaigns, :dispatch_started_at, :datetime
    add_index :lightek_marketing_contacts, :subscription_token_digest, unique: true
    create_table :lightek_marketing_social_connections do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.string :provider, null: false
      t.string :account_label, null: false
      t.string :publish_endpoint, null: false
      t.string :credential_key, null: false
      t.boolean :enabled, null: false, default: false
      t.timestamps
    end
    add_index :lightek_marketing_social_connections, [:site_id, :provider, :account_label], unique: true, name: "idx_marketing_social_connection"
    create_table :lightek_marketing_social_posts do |t|
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :connection, null: false, foreign_key: {to_table: :lightek_marketing_social_connections}
      t.string :status, null: false, default: "pending"
      t.string :remote_id
      t.text :error
      t.datetime :published_at
      t.timestamps
    end
    add_index :lightek_marketing_social_posts, [:campaign_id, :connection_id], unique: true, name: "idx_marketing_social_post"
  end
end
