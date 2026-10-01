class CreateLightekPwaStorefront < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_pwa_surfaces do |t|
      t.string :key, null: false
      t.string :surface_type, null: false
      t.string :label, null: false
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.jsonb :configuration, null: false, default: {}
      t.string :seed_namespace
      t.integer :seed_version

      t.timestamps
    end

    add_index :lightek_pwa_surfaces,
              :key,
              unique: true

    create_table :lightek_pwa_surface_modules do |t|
      t.references :surface,
                   null: false,
                   foreign_key: {
                     to_table: :lightek_pwa_surfaces
                   }

      t.string :key, null: false
      t.string :module_type, null: false
      t.string :label
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.string :data_source
      t.string :capability
      t.jsonb :configuration, null: false, default: {}
      t.string :seed_namespace
      t.integer :seed_version

      t.timestamps
    end

    add_index :lightek_pwa_surface_modules,
              [:surface_id, :key],
              unique: true,
              name: "idx_lightek_surface_modules_unique"

    create_table :lightek_pwa_navigation_items do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :surface_key
      t.string :href
      t.string :placement, null: false, default: "primary"
      t.integer :position, null: false, default: 0
      t.boolean :enabled, null: false, default: true
      t.string :requires_capability
      t.jsonb :configuration, null: false, default: {}
      t.string :seed_namespace
      t.integer :seed_version

      t.timestamps
    end

    add_index :lightek_pwa_navigation_items,
              :key,
              unique: true
  end
end
