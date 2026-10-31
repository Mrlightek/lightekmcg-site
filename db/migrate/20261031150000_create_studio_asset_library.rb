class CreateStudioAssetLibrary < ActiveRecord::Migration[8.0]
  def change
    create_table :studio_assets do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.references :site, foreign_key: { to_table: :dymond_site_sites }
      t.references :studio_project, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "uploaded"
      t.string :request_key, null: false
      t.jsonb :metadata, null: false, default: {}
      t.text :error_message
      t.timestamps
    end
    add_column :posts, :distribution, :string, null: false, default: "lightek_social"
    add_index :posts, %i[site_id distribution]
    add_index :studio_assets, %i[owner_id request_key], unique: true
  end
end
