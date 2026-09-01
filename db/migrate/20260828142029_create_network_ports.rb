class CreateNetworkPorts < ActiveRecord::Migration[8.0]
  def change
    create_table :network_ports do |t|
      t.integer :port, null: false
      t.string :protocol, null: false

      t.string :service
      t.string :host

      t.boolean :enabled,
                null: false,
                default: true

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :network_ports,
              [:port, :protocol],
              unique: true

    add_index :network_ports,
              :enabled
  end
end
