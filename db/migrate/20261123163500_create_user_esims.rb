class CreateUserEsims < ActiveRecord::Migration[8.0]
  def change
    create_table :user_esims do |t|
      t.references :user, null: false, foreign_key: true
      t.string :request_key, limit: 36, null: false
      t.string :sim_card_group_id, limit: 36, null: false
      t.string :telnyx_sim_id
      t.string :iccid
      t.string :lpa_activation_code
      t.string :assigned_private_ip
      t.string :customer_wg_peer_ip, null: false
      # Skip reserved Linux policy routing tables 253–255.
      t.virtual :routing_table_id, type: :integer, as: "CASE WHEN id < 154 THEN id + 99 ELSE id + 102 END", stored: true
      t.integer :plan_limit_mb, null: false
      t.integer :initial_plan_limit_mb, null: false
      t.string :status, null: false, default: "provisioning"
      t.string :carrier_status
      t.datetime :purchase_started_at
      t.datetime :limit_applied_at
      t.datetime :activation_requested_at
      t.datetime :route_installed_at
      t.timestamps
    end

    %i[request_key telnyx_sim_id iccid assigned_private_ip routing_table_id].each do |column|
      add_index :user_esims, column, unique: true
    end
    add_check_constraint :user_esims, "plan_limit_mb > 0", name: "user_esim_positive_limit"
    create_table :telnyx_esim_events do |t|
      t.references :user_esim, null: false, foreign_key: { on_delete: :cascade }
      t.string :event_id, limit: 36, null: false
      t.datetime :created_at, null: false
    end
    add_index :telnyx_esim_events, :event_id, unique: true
    add_check_constraint :user_esims, "routing_table_id >= 100", name: "user_esim_valid_table"
  end
end
