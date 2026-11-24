class CreateItServiceRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :it_service_requests do |t|
      t.references :user, null: false, index: true
      t.string :service_code, null: false
      t.string :delivery_mode, null: false
      t.string :status, null: false, default: "requested"
      t.string :device_platform
      t.text :description, null: false
      t.text :service_location
      t.text :resolution_notes
      t.datetime :closed_at
      t.timestamps
    end
    add_index :it_service_requests, [:user_id, :created_at]
    add_check_constraint :it_service_requests, "delivery_mode IN ('remote', 'onsite')", name: "it_service_delivery_mode"
  end
end
