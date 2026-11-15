class AddCampaignContentReview < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_marketing_campaigns, :production_format, :string, null: false, default: 'portrait'
    add_column :lightek_marketing_campaigns, :lock_version, :integer, null: false, default: 0
    add_column :lightek_marketing_campaigns, :content_review_required, :boolean, null: false, default: false
    add_column :lightek_marketing_campaigns, :approved_content_digest, :string
    add_reference :lightek_marketing_campaigns, :content_approved_by, foreign_key: {to_table: :users}
    add_column :lightek_marketing_campaigns, :content_approved_at, :datetime
    create_table :lightek_marketing_content_variants do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :approved_by, foreign_key: {to_table: :users}
      t.string :batch_key, :angle, :status, null: false
      t.string :headline, :cta_label, :cta_url, :media_url
      t.text :message
      t.string :applied_digest
      t.string :baseline_digest, null: false
      t.jsonb :source_snapshot, null: false, default: {}
      t.datetime :approved_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_marketing_content_variants, [:campaign_id, :batch_key, :angle], unique: true, name: 'idx_campaign_content_angle'
    add_column :lightek_marketing_deliveries, :content_digest, :string
  end
end
