class AddMarketingCopilot < ActiveRecord::Migration[8.0]
  class Agent < ActiveRecord::Base
    self.table_name = 'nevaeh_os_agents'
  end
  def up
    create_table :lightek_growth_marketing_kits do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :campaign, null: false, foreign_key: {to_table: :lightek_marketing_campaigns}
      t.string :request_key, null: false
      t.date :starts_on, null: false
      t.jsonb :options, null: false, default: {}
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_growth_marketing_kits, [:site_id, :request_key], unique: true, name: 'idx_marketing_kit_request'
    create_table :lightek_growth_marketing_check_ins do |t|
      t.references :marketing_kit, null: false, foreign_key: {to_table: :lightek_growth_marketing_kits}, index: false
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.integer :day_index, null: false
      t.string :status, null: false
      t.text :note, null: false
      t.timestamps
    end
    add_index :lightek_growth_marketing_check_ins, [:marketing_kit_id, :day_index], unique: true, name: 'idx_marketing_kit_day'
    create_table :lightek_growth_feature_showcases do |t|
      t.references :marketing_kit, null: false, foreign_key: {to_table: :lightek_growth_marketing_kits}, index: {unique: true}
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :page, null: false, foreign_key: {to_table: :dymond_site_pages}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :approved_by, foreign_key: {to_table: :users}
      t.string :status, null: false, default: 'pending'
      t.string :token, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.text :error
      t.datetime :approved_at
      t.timestamps
    end
    add_index :lightek_growth_feature_showcases, :token, unique: true
    create_table :lightek_growth_feature_clips do |t|
      t.references :feature_showcase, null: false, foreign_key: {to_table: :lightek_growth_feature_showcases}, index: false
      t.integer :position, null: false
      t.string :feature_key, :category, :title, null: false
      t.text :body, null: false
      t.string :checksum
      t.timestamps
    end
    add_index :lightek_growth_feature_clips, [:feature_showcase_id, :position], unique: true, name: 'idx_feature_clip_position'
    create_table :lightek_growth_marketing_executions do |t|
      t.references :marketing_kit, null: false, foreign_key: {to_table: :lightek_growth_marketing_kits}, index: {unique: true}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.references :goal, null: false, foreign_key: {to_table: :nevaeh_goals}
      t.timestamps
    end
    # Upgrade only the untouched default; retain deliberate restrictions.
    Agent.where(system_key: 'campaign', deleted_at: nil).find_each do |agent|
      agent.with_lock do
        if [ ['marketing.campaign.produce'], %w[marketing.campaign.produce growth.marketing_kit] ].include?(agent.allowed_capabilities)
          agent.update!(allowed_capabilities: %w[marketing.campaign.produce growth.marketing_kit growth.marketing_execute])
        end
      end
    end
  end
  def down
    raise ActiveRecord::IrreversibleMigration, 'Retain marketing kit, check-in and reviewed worker history.'
  end
end
