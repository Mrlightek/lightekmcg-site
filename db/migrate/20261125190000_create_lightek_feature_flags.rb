class CreateLightekFeatureFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_feature_flags do |t|
      t.string :key, null: false
      t.boolean :enabled, null: false, default: false
      t.boolean :staff, null: false, default: false
      t.integer :percentage, null: false, default: 0
      t.jsonb :account_ids, null: false, default: []
      t.jsonb :agency_ids, null: false, default: []
      t.jsonb :installation_ids, null: false, default: []
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_feature_flags, :key, unique: true
    add_check_constraint :lightek_feature_flags, "percentage BETWEEN 0 AND 100", name: "feature_flags_valid_percentage"

    create_table :lightek_feature_flag_changes do |t|
      t.references :flag, null: false, foreign_key: {to_table: :lightek_feature_flags}
      t.references :actor, null: false, foreign_key: {to_table: :users}
      t.jsonb :previous, null: false
      t.jsonb :current, null: false
      t.timestamps
    end
  end
end
