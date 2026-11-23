class LinkRoomsToSharedCalendarEvents < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_shared_events, :session_room, index: {unique: true},
      foreign_key: {to_table: :lightek_session_rooms}
  end
end
