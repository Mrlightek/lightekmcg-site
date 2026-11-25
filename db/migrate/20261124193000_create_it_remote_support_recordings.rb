class CreateItRemoteSupportRecordings < ActiveRecord::Migration[8.0]
  def change
    create_table :it_remote_support_recordings do |table|
      table.references :it_remote_support_session, null: false, foreign_key: true,
        index: { unique: true, name: "index_remote_recordings_on_session" }
      table.datetime :customer_consented_at
      table.datetime :technician_consented_at
      table.datetime :started_at
      table.datetime :revoked_at
      table.datetime :expires_at
      table.text :payload
      table.timestamps

      table.index :expires_at
    end
  end
end
