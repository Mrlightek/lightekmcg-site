class CreateLightekCommunicationsServices < ActiveRecord::Migration[8.0]
  def change
    create_table :lightek_communications_services do |t|
      t.references :subscription, null: false, index: { unique: true, name: "idx_communications_service_subscription" },
        foreign_key: { to_table: :lightek_commerce_subscriptions }
      t.string :kind, null: false
      t.string :status, null: false, default: "provisioning"
      t.timestamps
    end

    create_table :lightek_communications_service_events do |t|
      t.references :service, null: false, index: { name: "idx_communications_service_events" },
        foreign_key: { to_table: :lightek_communications_services }
      t.references :operator, null: false, foreign_key: { to_table: :users }
      t.references :billing_invoice, index: { name: "idx_communications_event_invoice" },
        foreign_key: { to_table: :lightek_commerce_billing_invoices }
      t.string :action, null: false
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
  end
end
