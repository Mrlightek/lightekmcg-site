class CreateLightekConnect < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_connect_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :label, null: false
      t.string :code_digest
      t.datetime :code_expires_at
      t.string :token_digest
      t.string :external_identity
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :lightek_connect_connections, :code_digest, unique: true
    add_index :lightek_connect_connections, :token_digest, unique: true
    create_table :lightek_connect_grants do |t|
      t.references :connection, null: false, foreign_key: {to_table: :lightek_connect_connections}
      t.string :destination, null: false, default: "/dashboard"
      t.references :site, foreign_key: {to_table: :dymond_site_sites}
      t.string :code_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :lightek_connect_grants, :code_digest, unique: true
    create_table :lightek_connect_events do |t|
      t.references :connection, foreign_key: {to_table: :lightek_connect_connections}
      t.string :action, null: false
      t.string :resource
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    add_column :sessions, :connect_delegation, :jsonb, null: false, default: {}
  end
end
