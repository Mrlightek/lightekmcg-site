class CreateInstallationCollaboration < ActiveRecord::Migration[8.0]
  def change
    add_reference :lightek_mail_accounts, :installation_peer, index: {unique: true},
      foreign_key: {to_table: :lightek_reservation_peers}

    create_table :lightek_team_network_channels do |t|
      t.references :host_peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.references :partner_peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.string :key, null: false
      t.string :name, null: false
      t.datetime :accepted_at
      t.datetime :closed_at
      t.timestamps
      t.index :key, unique: true
    end

    create_table :lightek_team_network_members do |t|
      t.references :channel, null: false, index: false, foreign_key: {to_table: :lightek_team_network_channels}
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.string :subject, null: false
      t.string :display_name, null: false, limit: 120
      t.index %i[channel_id peer_id subject], name: 'index_network_team_members_on_identity', unique: true
    end

    create_table :lightek_team_network_messages do |t|
      t.references :channel, null: false, index: false, foreign_key: {to_table: :lightek_team_network_channels}
      t.references :peer, null: false, foreign_key: {to_table: :lightek_reservation_peers}
      t.string :subject, null: false
      t.string :author, null: false
      t.string :request_key, null: false
      t.text :body, null: false
      t.timestamps
      t.index %i[channel_id id]
      t.index %i[channel_id peer_id subject request_key], name: 'index_network_team_messages_on_identity', unique: true
    end
  end
end
