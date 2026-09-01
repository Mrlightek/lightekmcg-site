class CreateNetworkEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :network_events do |t|
      t.string :name, null: false
      t.string :source
      t.string :destination
      t.string :transport

      t.boolean :enabled,
                null: false,
                default: true

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :network_events,
              :name,
              unique: true

    add_index :network_events,
              :enabled
  end
end