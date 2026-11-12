class AddDirectProductionRooms < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_session_rooms, :purpose, :string, default: 'booking', null: false
    add_reference :lightek_session_rooms, :host_user, foreign_key: {to_table: :users}
    add_check_constraint :lightek_session_rooms, "purpose IN ('booking', 'production') AND (purpose <> 'production' OR host_user_id IS NOT NULL)", name: 'session_room_purpose_valid'
  end
end
