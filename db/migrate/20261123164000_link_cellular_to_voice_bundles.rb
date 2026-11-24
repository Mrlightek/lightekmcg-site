class LinkCellularToVoiceBundles < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_voice_add_ons, :cellular_request_key, :string, limit: 36
    add_column :lightek_voice_add_ons, :cellular_peer_ip, :string
    add_column :lightek_voice_add_ons, :cellular_group_id, :string, limit: 36
    add_index :lightek_voice_add_ons, :cellular_request_key, unique: true
  end
end
