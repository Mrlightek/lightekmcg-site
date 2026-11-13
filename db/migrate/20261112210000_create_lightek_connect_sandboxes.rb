class CreateLightekConnectSandboxes < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_connect_sandboxes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :gatekeeper_node, null: false, foreign_key: true
      t.string :key, null: false
      t.string :domain, null: false
      t.string :status, null: false, default: "queued"
      t.string :credential_slug, null: false
      t.jsonb :metadata, null: false, default: {}
      t.string :error_message
      t.timestamps
    end
    add_index :lightek_connect_sandboxes, :key, unique: true
    add_index :lightek_connect_sandboxes, :domain, unique: true
  end
end
