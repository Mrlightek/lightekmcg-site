class CreateApplicationLaunches < ActiveRecord::Migration[8.0]
  def change
    create_table :gatekeeper_application_templates do |t|
      t.string :name, null: false
      t.string :preview_domain
      t.string :kind, null: false, default: "native_rails"
      t.string :image
      t.string :build_status, null: false, default: "ready"
      t.string :source_ref
      t.integer :container_port, null: false, default: 3000
      t.string :credential_slug
      t.boolean :rails_database, null: false, default: true
      t.boolean :rails_worker, null: false, default: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    create_table :gatekeeper_application_launches do |t|
      t.references :gatekeeper_application_template, null: false, foreign_key: true
      t.references :gatekeeper_node, foreign_key: true
      t.references :provisioning_request, foreign_key: true
      t.references :owner, null: false, foreign_key: {to_table: :users}
      t.references :requested_by, null: false, foreign_key: {to_table: :users}
      t.string :name, null: false
      t.string :domain, null: false
      t.string :status, null: false, default: "queued"
      t.text :error_message
      t.jsonb :receipt, null: false, default: {}
      t.jsonb :template_snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :gatekeeper_application_launches, :domain, unique: true
    add_index :gatekeeper_application_launches, [:status, :updated_at]
  end
end
