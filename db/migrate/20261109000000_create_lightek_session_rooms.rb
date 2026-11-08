class CreateLightekSessionRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_session_rooms do |t|
      t.references :resource, null: false, foreign_key: {to_table: :lightek_reservation_resources}
      t.string :key, null: false
      t.string :media_name, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.string :status, null: false, default: 'scheduled'
      t.boolean :locked, null: false, default: false
      t.boolean :broadcast_consent, null: false, default: false
      t.timestamps
    end
    add_index :lightek_session_rooms, :key, unique: true
    add_index :lightek_session_rooms, [:resource_id, :starts_at, :ends_at], unique: true, name: 'idx_lightek_room_slot'
    create_table :lightek_session_members do |t|
      t.references :room, null: false, foreign_key: {to_table: :lightek_session_rooms}
      t.references :user, null: false, foreign_key: true
      t.references :reservation, foreign_key: {to_table: :lightek_reservations}
      t.string :status, null: false, default: 'waiting'
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :lightek_session_members, [:room_id, :user_id], unique: true
  end
end
