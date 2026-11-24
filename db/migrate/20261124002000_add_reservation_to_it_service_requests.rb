class AddReservationToItServiceRequests < ActiveRecord::Migration[8.0]
  def change
    add_reference :it_service_requests, :reservation, null: true,
      foreign_key: { to_table: :lightek_reservations }, index: { unique: true }
  end
end
