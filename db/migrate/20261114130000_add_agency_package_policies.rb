class AddAgencyPackagePolicies < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_commerce_products, :source_hosting_package, foreign_key: {to_table: :hosting_packages}
    add_column :lightek_commerce_products, :package_policy, :jsonb, null: false, default: {}
    create_table :lightek_agency_installed_packages do |t|
      t.references :user, null: false, foreign_key: true, index: {unique: true}
      t.string :source_key, null: false
      t.boolean :runtime, null: false, default: false
      t.jsonb :policy, null: false, default: {}
      t.timestamps
    end
    create_table :lightek_agency_package_usages do |t|
      t.references :installed_package, null: false, foreign_key: {to_table: :lightek_agency_installed_packages}
      t.string :feature, null: false
      t.date :period, null: false
      t.bigint :used, null: false, default: 0
      t.timestamps
    end
    add_index :lightek_agency_package_usages, [:installed_package_id, :feature, :period], unique: true, name: :index_package_usage_on_account_feature_period
    create_table :lightek_agency_package_storage do |t|
      t.references :installed_package, null: false, foreign_key: {to_table: :lightek_agency_installed_packages}
      t.bigint :blob_id, null: false
      t.bigint :bytes, null: false
      t.timestamps
    end
    add_index :lightek_agency_package_storage, [:installed_package_id, :blob_id], unique: true, name: :index_package_storage_on_account_blob
  end
end
