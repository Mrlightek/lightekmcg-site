class CreateComputeProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :compute_providers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :adapter_type, null: false, default: "declarative"
      t.string :adapter_class
      t.string :api_base_url
      t.string :documentation_url
      t.string :openapi_url
      t.string :credential_secret_slug
      t.string :status, null: false, default: "draft"
      t.string :health_status, null: false, default: "unknown"
      t.datetime :last_healthcheck_at
      t.jsonb :capabilities, null: false, default: {}
      t.jsonb :configuration, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :compute_providers, :slug, unique: true
    add_index :compute_providers, :status
    add_index :compute_providers, :health_status
    add_index :compute_providers, :capabilities, using: :gin
    add_index :compute_providers, :configuration, using: :gin
  end
end
