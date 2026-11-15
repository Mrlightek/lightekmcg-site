class AddDailyGrowthPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_growth_plans do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :created_by, null: false, foreign_key: {to_table: :users}
      t.references :previous_plan, foreign_key: {to_table: :lightek_growth_plans}
      t.date :plan_on, null: false
      t.integer :revision, null: false, default: 1
      t.string :request_key, null: false
      t.string :playbook_version, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :lightek_growth_plans, [:site_id, :plan_on, :revision], unique: true, name: 'idx_growth_plan_revision'
    add_index :lightek_growth_plans, [:site_id, :request_key], unique: true, name: 'idx_growth_plan_request'
    create_table :lightek_growth_steps do |t|
      t.references :site, null: false, foreign_key: {to_table: :dymond_site_sites}
      t.references :plan, null: false, foreign_key: {to_table: :lightek_growth_plans}
      t.string :key, null: false
      t.integer :position, null: false
      t.jsonb :definition, null: false, default: {}
      t.string :status, null: false, default: 'open'
      t.text :resolution_note
      t.string :resolution_source
      t.references :resolved_by, foreign_key: {to_table: :users}
      t.datetime :resolved_at
      t.jsonb :result, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_growth_steps, [:plan_id, :key], unique: true
  end
end
