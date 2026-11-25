class AddTechnicianToItServiceRequests < ActiveRecord::Migration[8.0]
  def change
    add_reference :it_service_requests, :technician, foreign_key: { to_table: :users }, index: true
    add_column :it_service_requests, :technician_assigned_at, :datetime
  end
end
