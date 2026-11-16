class AddCampaignPerformanceComparisons < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_comparisons do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.string :request_key, :name, :variable, null: false
      t.text :hypothesis, null: false
      t.date :starts_on, :ends_on, null: false
      t.jsonb :brief_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_growth_comparisons, [:site_id, :request_key], unique: true, name: 'idx_growth_comparison_request'
    create_table :lightek_growth_comparison_arms do |t|
      t.references :comparison, null: false, foreign_key: {to_table: :lightek_growth_comparisons}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :link, null: false, foreign_key: {to_table: :lightek_growth_links}, index: {unique: true}
      t.string :label, :content_digest, null: false
      t.jsonb :creative_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_growth_comparison_arms, [:comparison_id, :label], unique: true, name: 'idx_growth_comparison_arm'
    create_table :lightek_growth_performance_reviews do |t|
      t.references :comparison, null: false, foreign_key: {to_table: :lightek_growth_comparisons}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.string :request_key, :rules_version, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :measured_at, null: false
      t.timestamps
    end
    add_index :lightek_growth_performance_reviews, [:comparison_id, :request_key], unique: true, name: 'idx_growth_performance_review_request'
    create_table :lightek_growth_performance_drafts do |t|
      t.references :review, null: false, foreign_key: {to_table: :lightek_growth_performance_reviews}, index: {unique: true}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.timestamps
    end
  end
end
