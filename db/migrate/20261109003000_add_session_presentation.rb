class AddSessionPresentation < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_session_rooms, :presentation, :jsonb, null: false, default: {}
  end
end
