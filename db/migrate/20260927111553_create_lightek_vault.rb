class CreateLightekVault < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_vault_secrets do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :secret_type, null: false, default: "credential"
      t.string :provider
      t.string :environment, null: false, default: "production"
      t.string :purpose
      t.string :status, null: false, default: "active"
      t.text :ciphertext, null: false
      t.text :encrypted_data_key, null: false
      t.string :payload_iv, null: false
      t.string :payload_tag, null: false
      t.string :key_iv, null: false
      t.string :key_tag, null: false
      t.integer :key_version, null: false, default: 1
      t.jsonb :access_policy, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :last_used_at
      t.datetime :last_rotated_at
      t.datetime :expires_at
      t.datetime :disabled_at
      t.timestamps
    end

    add_index :lightek_vault_secrets, :slug, unique: true
    add_index :lightek_vault_secrets, :provider
    add_index :lightek_vault_secrets, :status
    add_index :lightek_vault_secrets, :expires_at
    add_index :lightek_vault_secrets, :access_policy, using: :gin
    add_index :lightek_vault_secrets, :metadata, using: :gin

    create_table :lightek_vault_audit_events do |t|
      t.references :secret, null: false, foreign_key: { to_table: :lightek_vault_secrets }
      t.string :action, null: false
      t.string :consumer
      t.string :purpose
      t.string :requested_by
      t.string :gatekeeper_operation_id
      t.boolean :allowed, null: false, default: false
      t.string :reason
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :lightek_vault_audit_events, :action
    add_index :lightek_vault_audit_events, :created_at
  end
end
