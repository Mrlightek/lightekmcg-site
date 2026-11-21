class ConnectManagedBroadcastInstallations < ActiveRecord::Migration[8.0]
  def change
    add_column :studio_network_carriages, :remote_key, :string
    add_column :studio_network_carriages, :relay_digest, :string
    add_index :studio_network_carriages, :remote_key, unique: true
    create_table :studio_hosted_carriages do |t|
      t.references :peer, null: false, foreign_key: { to_table: :lightek_reservation_peers }
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "requested"
      t.string :ownership
      t.boolean :published, null: false, default: false
      t.jsonb :schedule, default: [], null: false
      t.timestamps
      t.index :key, unique: true
      t.index %i[status published]
    end
  end
end
