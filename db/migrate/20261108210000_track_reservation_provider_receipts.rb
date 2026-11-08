class TrackReservationProviderReceipts < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_reservation_changes, :provider_receipt, :jsonb, null: false, default: {}
  end
end
