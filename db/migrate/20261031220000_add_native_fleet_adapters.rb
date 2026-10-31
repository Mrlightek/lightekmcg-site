class AddNativeFleetAdapters < ActiveRecord::Migration[8.0]
  def change
    add_column :gatekeeper_installations, :adapter, :string, null: false, default: "native_rails"
    add_column :gatekeeper_installations, :component, :string, null: false, default: "lightek_app"
    add_column :gatekeeper_installations, :repository, :string, null: false, default: "https://github.com/Mrlightek/lightekmcg-site.git"
    add_column :gatekeeper_installations, :deployment_config, :jsonb, null: false, default: {}
    add_reference :gatekeeper_installations, :account, foreign_key: {to_table: :users}
    add_reference :gatekeeper_installations, :pinned_release, foreign_key: {to_table: :gatekeeper_releases}
    add_reference :gatekeeper_installations, :gatekeeper_project, foreign_key: true
    remove_index :gatekeeper_installations, :domain, unique: true
    add_index :gatekeeper_installations, [:gatekeeper_node_id, :domain, :component], unique: true, name: "index_fleet_installation_component"
    add_column :gatekeeper_releases, :adapter, :string, null: false, default: "native_rails"
    add_column :gatekeeper_releases, :component, :string, null: false, default: "lightek_app"
    add_column :gatekeeper_releases, :repository, :string, null: false, default: "https://github.com/Mrlightek/lightekmcg-site.git"
    change_column_null :gatekeeper_releases, :image, true
    reversible do |direction|
      direction.up { execute "UPDATE gatekeeper_releases SET adapter = 'docker_compose' WHERE image IS NOT NULL AND image <> ''" }
    end
  end
end
