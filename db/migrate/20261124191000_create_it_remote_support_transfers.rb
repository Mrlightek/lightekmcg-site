class CreateItRemoteSupportTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :it_remote_support_transfers do |t|
      t.references :it_remote_support_session, null: false, foreign_key: true, index: { name: "index_remote_transfers_on_session" }
      t.references :sender, null: false, foreign_key: { to_table: :users }, index: false
      t.string :filename, null: false
      t.string :media_type, null: false
      t.string :sha256, null: false
      t.integer :byte_size, null: false
      t.string :state, null: false
      t.text :payload
      t.timestamps
    end

    add_check_constraint :it_remote_support_transfers, "byte_size BETWEEN 1 AND 1048576", name: "remote_transfer_size"
    add_check_constraint :it_remote_support_transfers,
      "state IN ('scanning', 'awaiting_acceptance', 'accepted', 'downloaded', 'cancelled', 'quarantined', 'scan_failed')",
      name: "remote_transfer_state"
    add_check_constraint :it_remote_support_transfers,
      "(payload IS NOT NULL) = (state IN ('scanning', 'awaiting_acceptance', 'accepted'))", name: "remote_transfer_payload_state"
  end
end
