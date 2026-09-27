class AddExecutionFieldsToProvisioningRequests < ActiveRecord::Migration[8.0]
  def change
    change_table :provisioning_requests, bulk: true do |t|
      t.string :selected_region
      t.string :selected_plan
      t.string :selected_image
      t.string :node_label
      t.references :gatekeeper_node, foreign_key: true
      t.string :destroy_approval_status, null: false, default: "not_requested"
      t.string :destroy_approved_by
      t.datetime :destroy_approved_at
      t.datetime :provisioned_at
      t.datetime :destroyed_at
    end

    add_index :provisioning_requests, :destroy_approval_status
  end
end
