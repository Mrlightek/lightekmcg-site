class CreateMarketplaceProductGroupsAndServiceConnections < ActiveRecord::Migration[8.0]
  def up
    create_table :lightek_marketplace_product_groups do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :lightek_marketplace_product_groups, :key, unique: true, name: "idx_marketplace_group_key"
    create_table :lightek_marketplace_customer_services do |t|
      t.string :name, null: false
      t.text :description, null: false
      t.string :feature_key, null: false
      t.string :customer_path, null: false
      t.boolean :active, null: false, default: false
      t.bigint :reviewed_by_id
      t.datetime :reviewed_at
      t.timestamps
    end
    base = {"cloud" => "Cloud & Websites", "entertainment" => "Entertainment", "finance" => "Dymond Bank", "creators" => "Creator Tools"}
    select_values("SELECT DISTINCT category FROM dymond_catalog_marketplace_listings").each do |key|
      base[key] ||= key.to_s.tr("_", " ").split.map(&:capitalize).join(" ")
    end
    base.each_with_index do |(key, name), position|
      execute <<~SQL
        INSERT INTO lightek_marketplace_product_groups (key, name, position, active, created_at, updated_at)
        VALUES (#{connection.quote(key)}, #{connection.quote(name)}, #{position}, #{connection.quoted_true}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end
  def down
    drop_table :lightek_marketplace_customer_services
    drop_table :lightek_marketplace_product_groups
  end
end
