class RecordCreatorTransferAttempts < ActiveRecord::Migration[8.0]
  def change
    add_column :lightek_pwa_creator_earnings, :transfer_requested_at, :datetime
  end
end
