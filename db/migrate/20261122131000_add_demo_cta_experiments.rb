class AddDemoCtaExperiments < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_growth_feature_showcases, :demo_experiment_started_at, :datetime
    create_table :lightek_growth_demo_exposures do |t|
      t.references :showcase, null: false, foreign_key: { to_table: :lightek_growth_feature_showcases }
      t.references :visit, null: false, foreign_key: { to_table: :lightek_growth_visits }
      t.string :variant, null: false
      t.timestamps
    end
    add_index :lightek_growth_demo_exposures, [:showcase_id, :visit_id], unique: true
  end
end
