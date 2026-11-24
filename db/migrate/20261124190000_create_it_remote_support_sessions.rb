class CreateItRemoteSupportSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :it_remote_support_sessions do |t|
      t.bigint :it_service_request_id, null: false, index: true
      t.references :customer, null: false, foreign_key: { to_table: :users }, index: false
      t.references :technician, null: false, foreign_key: { to_table: :users }, index: false
      t.bigint :technician_session_id, null: false
      t.bigint :customer_session_id
      t.string :state, null: false, default: "requested"
      t.datetime :expires_at, null: false
      t.datetime :consented_at
      t.datetime :ended_at
      t.string :end_reason
      t.text :offer_sdp
      t.text :answer_sdp
      t.timestamps

      t.index [:state, :expires_at]
      %i[customer_id technician_id].each do |participant|
        t.index participant, unique: true, where: "state IN ('requested', 'approved')",
          name: "index_it_remote_support_open_on_#{participant}"
      end
    end
  end
end
